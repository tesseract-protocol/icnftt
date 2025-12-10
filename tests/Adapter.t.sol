// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC721TokenHome} from "../contracts/adapter/TokenHome/ERC721TokenHome.sol";
import {ERC721TokenRemote} from "../contracts/adapter/TokenRemote/ERC721TokenRemote.sol";
import {TransferrerMessageType} from "../contracts/adapter/interfaces/IERC721Transferrer.sol";
import {SendTokenInput, SendAndCallInput} from "../contracts/adapter/interfaces/IERC721Transferrer.sol";
import {TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {MockTeleporterMessenger, MockTeleporterRegistry, MockWarpMessenger} from "./Mocks.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC721SendAndCallReceiver} from "../contracts/adapter/interfaces/IERC721SendAndCallReceiver.sol";

contract SimpleERC721 is ERC721URIStorage {
    string private _baseTokenURI;

    constructor(string memory name, string memory symbol, string memory baseURI) ERC721(name, symbol) {
        _baseTokenURI = baseURI;
    }

    function mint(address to, uint256 tokenId, string memory tokenURI_) external {
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function updateTokenURI(uint256 tokenId, string memory newURI) external {
        require(_ownerOf(tokenId) != address(0), "ERC721: URI update for nonexistent token");
        _setTokenURI(tokenId, newURI);
    }

    function setBaseURI(
        string memory newBaseURI
    ) external {
        _baseTokenURI = newBaseURI;
    }
}

contract ERC721TokenHomePublicMint is ERC721TokenHome {
    SimpleERC721 private _homeToken;

    constructor(
        address homeTokenAddress,
        address teleporterRegistryAddress,
        address teleporterManager,
        uint256 minTeleporterVersion
    ) ERC721TokenHome(homeTokenAddress, teleporterRegistryAddress, teleporterManager, minTeleporterVersion) {
        _homeToken = SimpleERC721(homeTokenAddress);
    }

    function _prepareTokenMetadata(
        uint256 tokenId,
        TransferrerMessageType
    ) internal view override returns (bytes memory) {
        bytes memory uriData = abi.encode(_homeToken.tokenURI(tokenId));
        return uriData;
    }
}

contract TokenRemote is ERC721TokenRemote, ERC721URIStorage {
    constructor(
        string memory name,
        string memory symbol,
        bytes32 homeChainId,
        address homeTokenAddress,
        address teleporterRegistryAddress,
        address teleporterManager,
        uint256 minTeleporterVersion
    )
        ERC721TokenRemote(
            name,
            symbol,
            homeChainId,
            homeTokenAddress,
            teleporterRegistryAddress,
            teleporterManager,
            minTeleporterVersion
        )
    {}

    function _processTokenMetadata(uint256 tokenId, bytes memory metadata) internal override {
        if (metadata.length > 0) {
            string memory uri = abi.decode(metadata, (string));
            _setTokenURI(tokenId, uri);
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view override (ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override (ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override (ERC721TokenRemote, ERC721) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "";
    }
}

contract MockERC721Receiver is IERC721SendAndCallReceiver {
    // Records of received tokens
    struct ReceivedToken {
        bytes32 sourceBlockchainID;
        address originTokenTransferrerAddress;
        address originSenderAddress;
        address tokenAddress;
        uint256[] tokenIds;
        bytes payload;
    }

    // Last received token details
    ReceivedToken public lastReceivedToken;

    // Count of received tokens
    uint256 public receiveCount;

    // Record of the payload
    bytes public lastPayload;

    function receiveTokens(
        bytes32 sourceBlockchainID,
        address originTokenTransferrerAddress,
        address originSenderAddress,
        address tokenAddress,
        uint256[] calldata tokenIds,
        bytes calldata payload
    ) external override {
        // Record token details first
        lastReceivedToken = ReceivedToken({
            sourceBlockchainID: sourceBlockchainID,
            originTokenTransferrerAddress: originTokenTransferrerAddress,
            originSenderAddress: originSenderAddress,
            tokenAddress: tokenAddress,
            tokenIds: tokenIds,
            payload: payload
        });

        // Store the payload for inspection
        lastPayload = payload;

        // Increment receive count
        receiveCount += tokenIds.length;

        // Accept all tokens - MUST transfer them from the token contract that called us
        for (uint256 i = 0; i < tokenIds.length; i++) {
            try ERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenIds[i]) {
                // Transfer successful
            } catch Error(string memory reason) {
                revert(string.concat("Transfer failed: ", reason));
            } catch {
                revert("Transfer failed without reason");
            }
        }
    }
}

contract HomeReentrancyContract {
    ERC721TokenHomePublicMint public homeToken;
    SimpleERC721 public homeNFT;
    TokenRemote public remoteToken;
    bytes32 constant REMOTE_CHAIN_ID = bytes32(uint256(2));

    constructor(ERC721TokenHomePublicMint _homeToken, TokenRemote _remoteToken, SimpleERC721 _homeNFT){
        homeToken = _homeToken;
        remoteToken = _remoteToken;
        homeNFT = _homeNFT;
    }

    function receiveTokens(
        bytes32 sourceBlockchainID,
        address originTokenTransferrerAddress,
        address originSenderAddress,
        address tokenAddress,
        uint256[] calldata tokenIds,
        bytes calldata payload
    ) external{
        console.log("HomeReentrancyContract: receiveTokens");
        homeNFT.transferFrom(msg.sender, address(this), 1);

        uint256[] memory tokenIds_ = new uint256[](1);

        tokenIds_[0] = 1;

        homeNFT.approve(address(homeToken), 1);

        console.log("HomeReentrancyContract: sending token to remote chain");

        homeToken.send(SendTokenInput({
            destinationBlockchainID: REMOTE_CHAIN_ID,
            destinationTokenTransferrerAddress: address(remoteToken),
            recipient: address(this),
            primaryFeeTokenAddress: address(0),
            primaryFee: 0,
            requiredGasLimit: 0
        }), tokenIds);
    }
}

contract Adapter_Test is Test {
    // Contracts under test
    SimpleERC721 public homeNFT;
    ERC721TokenHomePublicMint public homeToken;
    TokenRemote public remoteToken;

    // Mock contracts
    MockTeleporterMessenger teleporterMessenger;
    MockTeleporterRegistry teleporterRegistry;
    MockERC721Receiver homeReceiver;
    MockERC721Receiver remoteReceiver;

    // Chain IDs
    bytes32 constant HOME_CHAIN_ID = bytes32(uint256(1));
    bytes32 constant REMOTE_CHAIN_ID = bytes32(uint256(2));

    // Precompile address for IWarpMessenger
    address constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

    // Test addresses
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address feeToken = address(4);
    address operator = address(5);

    function setUp() public {
        // Setup the mock teleporter messenger with home chain ID
        teleporterMessenger = new MockTeleporterMessenger(HOME_CHAIN_ID, REMOTE_CHAIN_ID);

        // Setup the mock teleporter registry that points to our messenger
        teleporterRegistry = new MockTeleporterRegistry(address(teleporterMessenger));

        // Deploy mock warp messenger for home chain
        MockWarpMessenger homeMockWarp = new MockWarpMessenger(HOME_CHAIN_ID);
        vm.etch(WARP_PRECOMPILE, address(homeMockWarp).code);

        // Setup home NFT contract first
        vm.startPrank(owner);
        homeNFT = new SimpleERC721("HomeNFT", "HNFT", "https://home.nft/");

        // Then setup home token contract that wraps the NFT
        homeToken = new ERC721TokenHomePublicMint(
            address(homeNFT),
            address(teleporterRegistry),
            owner,
            1 // minTeleporterVersion
        );
        vm.stopPrank();

        // Change the mock warp messenger for remote chain
        MockWarpMessenger remoteMockWarp = new MockWarpMessenger(REMOTE_CHAIN_ID);
        vm.etch(WARP_PRECOMPILE, address(remoteMockWarp).code);

        // Setup remote token contract
        vm.startPrank(owner);
        remoteToken = new TokenRemote(
            "RemoteNFT",
            "RNFT",
            HOME_CHAIN_ID,
            address(homeToken),
            address(teleporterRegistry),
            owner,
            1 // minTeleporterVersion
        );
        vm.stopPrank();

        // Setup receiver contracts for both home and remote chains
        homeReceiver = new MockERC721Receiver();
        remoteReceiver = new MockERC721Receiver();
    }

    // Helper function to process teleporter messages
    function processNextTeleporterMessage(bytes32 destinationChainID, address destinationAddress) internal {
        require(teleporterMessenger.hasPendingMessages(destinationChainID, destinationAddress), "No pending messages");
        teleporterMessenger.deliverNextMessage(destinationChainID, destinationAddress);
    }

    // Helper function to register remote chain with home and sync the baseURI
    function _registerRemoteChain() internal {
        // First set the expected remote contract
        vm.prank(owner);
        homeToken.setExpectedRemoteContract(REMOTE_CHAIN_ID, address(remoteToken));

        // Register remote chain with home
        vm.prank(owner);
        remoteToken.registerWithHome(TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));

        // Deliver the register message from remote to home
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));
    }

    // Test remote chain registration process
    function testRegisterRemote() public {
        // Start with no registered chains
        bytes32[] memory initialChains = homeToken.getRegisteredChains();
        assertEq(initialChains.length, 0);

        // Set the expected remote contract
        vm.prank(owner);
        homeToken.setExpectedRemoteContract(REMOTE_CHAIN_ID, address(remoteToken));

        // Register remote with home
        vm.prank(owner);
        remoteToken.registerWithHome(TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));

        // Verify message was sent from remote to home
        assertTrue(teleporterMessenger.hasPendingMessages(HOME_CHAIN_ID, address(homeToken)));

        // Process the register message at home
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify home contract registered the remote chain
        bytes32[] memory registeredChains = homeToken.getRegisteredChains();
        assertEq(registeredChains.length, 1);
        assertEq(registeredChains[0], REMOTE_CHAIN_ID);
    }

    // Test remote chain registration process with unset expected contract
    function testRegisterRemoteUnexpected() public {
        // Start with no registered chains
        bytes32[] memory initialChains = homeToken.getRegisteredChains();
        assertEq(initialChains.length, 0);

        // Try to register remote with home without setting expected contract
        vm.prank(owner);
        remoteToken.registerWithHome(TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));

        // Verify message was sent from remote to home
        assertTrue(teleporterMessenger.hasPendingMessages(HOME_CHAIN_ID, address(homeToken)));

        // Process the register message at home - should fail
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify home contract did not register the remote chain
        bytes32[] memory registeredChains = homeToken.getRegisteredChains();
        assertEq(registeredChains.length, 0);
    }

    // Test remote chain registration process with wrong address
    function testRegisterRemoteWrongAddress() public {
        // Start with no registered chains
        bytes32[] memory initialChains = homeToken.getRegisteredChains();
        assertEq(initialChains.length, 0);

        // Set the expected remote contract with wrong address
        vm.prank(owner);
        homeToken.setExpectedRemoteContract(REMOTE_CHAIN_ID, address(0x1234));

        // Register remote with home
        vm.prank(owner);
        remoteToken.registerWithHome(TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));

        // Verify message was sent from remote to home
        assertTrue(teleporterMessenger.hasPendingMessages(HOME_CHAIN_ID, address(homeToken)));

        // Process the register message at home - should fail
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify home contract did not register the remote chain
        bytes32[] memory registeredChains = homeToken.getRegisteredChains();
        assertEq(registeredChains.length, 0);
    }

    // Test expected remote contract management
    function testExpectedRemoteContractManagement() public {
        // Test setting expected contract
        vm.prank(owner);
        homeToken.setExpectedRemoteContract(REMOTE_CHAIN_ID, address(remoteToken));
        assertEq(homeToken.getExpectedRemoteContract(REMOTE_CHAIN_ID), address(remoteToken));

        // Test removing expected contract
        vm.prank(owner);
        homeToken.setExpectedRemoteContract(REMOTE_CHAIN_ID, address(0));
        assertEq(homeToken.getExpectedRemoteContract(REMOTE_CHAIN_ID), address(0));
        
        // Test non-owner cannot set expected contract
        vm.prank(user1);
        vm.expectRevert();
        homeToken.setExpectedRemoteContract(REMOTE_CHAIN_ID, address(remoteToken));
    }

    // Test sending token from home to remote
    function testSendTokenFromHomeToRemote() public {
        // First register the remote chain with the home contract
        _registerRemoteChain();

        // User1 mints a token directly on the NFT contract
        vm.prank(user1);
        homeNFT.mint(user1, 1, "token1.json");

        // User sends token to remote chain through the wrapper
        vm.startPrank(user1);
        homeNFT.approve(address(homeToken), 1); // Approve the wrapper to transfer the token
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );
        vm.stopPrank();

        // Check token is now owned by the home contract instead of being locked
        assertEq(homeNFT.ownerOf(1), address(homeToken));

        // Verify message was sent from home to remote
        assertTrue(teleporterMessenger.hasPendingMessages(REMOTE_CHAIN_ID, address(remoteToken)));

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify token exists on remote chain
        assertEq(remoteToken.ownerOf(1), user1);
    }

    // Test sending token from remote back to home
    function testReturnTokenFromRemoteToHome() public {
        // First register and send a token to remote
        _registerRemoteChain();

        // User1 mints a token directly on the NFT contract
        vm.prank(user1);
        homeNFT.mint(user1, 1, "token1.json");

        // User sends token to remote chain through the wrapper
        vm.startPrank(user1);
        homeNFT.approve(address(homeToken), 1); // Approve the wrapper to transfer the token
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );
        vm.stopPrank();

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Now user sends token back from remote to home
        vm.prank(user1);
        remoteToken.send(
            SendTokenInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );

        // Verify token is burned on remote
        vm.expectRevert();
        remoteToken.ownerOf(1);

        // Verify message was sent from remote to home
        assertTrue(teleporterMessenger.hasPendingMessages(HOME_CHAIN_ID, address(homeToken)));

        // Process the message at home
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify token is transferred back to user1 (instead of being unlocked)
        assertEq(homeNFT.ownerOf(1), user1);
    }

    // Test that token URI is preserved when sending to remote
    function testTokenURIPreservedWhenSendingToRemote() public {
        _registerRemoteChain();

        // User1 mints a token with a custom URI
        vm.prank(user1);
        homeNFT.mint(user1, 1, "special-token.json");

        // Verify initial URI on home
        string memory initialHomeURI = string.concat("https://home.nft/", "special-token.json");
        assertEq(homeNFT.tokenURI(1), initialHomeURI);

        // Send token to remote
        vm.startPrank(user1);
        homeNFT.approve(address(homeToken), 1); // Approve the wrapper to transfer the token
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );
        vm.stopPrank();

        // Process the message
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify the token URI is preserved on remote
        assertEq(remoteToken.tokenURI(1), initialHomeURI);

        // Send back to home to another user
        vm.prank(user1);
        remoteToken.send(
            SendTokenInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipient: user2,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );

        // Process the return message
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify the token URI is still preserved after round trip
        assertEq(homeNFT.tokenURI(1), initialHomeURI);
    }

    // Test updating a token's URI
    function testUpdateTokenURI() public {
        // User1 mints a token directly on the NFT contract
        vm.prank(user1);
        homeNFT.mint(user1, 1, "token1.json");

        // Initial URI should combine baseURI and token URI
        string memory initialURI = string.concat("https://home.nft/", "token1.json");
        assertEq(homeNFT.tokenURI(1), initialURI);

        // Owner updates the token URI directly on the NFT contract
        vm.prank(owner);
        homeNFT.updateTokenURI(1, "updated-token1.json");

        // Verify the token URI was updated
        string memory updatedURI = string.concat("https://home.nft/", "updated-token1.json");
        assertEq(homeNFT.tokenURI(1), updatedURI);
    }

    function testTransferMultipleTokens() public {
        _registerRemoteChain();

        // User1 mints multiple tokens
        vm.startPrank(user1);
        homeNFT.mint(user1, 1, "token1.json");
        homeNFT.mint(user1, 2, "token2.json");
        homeNFT.mint(user1, 3, "token3.json");

        // Approve all tokens
        homeNFT.approve(address(homeToken), 1);
        homeNFT.approve(address(homeToken), 2);
        homeNFT.approve(address(homeToken), 3);

        // Create array of token IDs
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        // Send multiple tokens to remote chain
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );
        vm.stopPrank();

        // Check all tokens are now owned by the home contract
        assertEq(homeNFT.ownerOf(1), address(homeToken));
        assertEq(homeNFT.ownerOf(2), address(homeToken));
        assertEq(homeNFT.ownerOf(3), address(homeToken));

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify all tokens exist on remote chain
        assertEq(remoteToken.ownerOf(1), user1);
        assertEq(remoteToken.ownerOf(2), user1);
        assertEq(remoteToken.ownerOf(3), user1);

        // Send tokens back to home
        vm.prank(user1);
        remoteToken.send(
            SendTokenInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipient: user2,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            tokenIds
        );

        // Verify tokens are burned on remote
        vm.expectRevert();
        remoteToken.ownerOf(1);
        vm.expectRevert();
        remoteToken.ownerOf(2);
        vm.expectRevert();
        remoteToken.ownerOf(3);

        // Process the return message
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify all tokens are transferred to user2
        assertEq(homeNFT.ownerOf(1), user2);
        assertEq(homeNFT.ownerOf(2), user2);
        assertEq(homeNFT.ownerOf(3), user2);
    }

    function testSendAndCall() public {
        _registerRemoteChain();

        // User1 mints tokens
        vm.startPrank(user1);
        homeNFT.mint(user1, 1, "token1.json");
        homeNFT.mint(user1, 2, "token2.json");

        // Approve tokens
        homeNFT.approve(address(homeToken), 1);
        homeNFT.approve(address(homeToken), 2);

        // Create array of token IDs
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        // Send tokens with contract call
        bytes memory receiverPayload = abi.encode("test data");
        homeToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipientContract: address(remoteReceiver),
                recipientPayload: receiverPayload,
                recipientGasLimit: 800000,
                fallbackRecipient: user2,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 900000
            }),
            tokenIds
        );
        vm.stopPrank();

        // Check tokens are owned by home contract
        assertEq(homeNFT.ownerOf(1), address(homeToken), "Token 1 not owned by home contract");
        assertEq(homeNFT.ownerOf(2), address(homeToken), "Token 2 not owned by home contract");

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify tokens are owned by the receiver contract
        assertEq(remoteToken.ownerOf(1), address(remoteReceiver), "Token 1 not owned by receiver contract");
        assertEq(remoteToken.ownerOf(2), address(remoteReceiver), "Token 2 not owned by receiver contract");

        // Send tokens back to home with contract call
        vm.prank(address(remoteReceiver));
        remoteToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipientContract: address(homeReceiver),
                recipientPayload: receiverPayload,
                recipientGasLimit: 800000,
                fallbackRecipient: user2,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 900000
            }),
            tokenIds
        );

        // Process the return message
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify tokens are owned by the home receiver contract
        assertEq(homeNFT.ownerOf(1), address(homeReceiver));
        assertEq(homeNFT.ownerOf(2), address(homeReceiver));
    }

    function testSendAndCallReentrancy() public {
        _registerRemoteChain();

        // User1 mints tokens
        vm.startPrank(user1);
        homeNFT.mint(user1, 1, "token1.json");

        // Approve tokens
        homeNFT.approve(address(homeToken), 1);

        assertEq(homeNFT.ownerOf(1), user1);
        vm.expectRevert();
        remoteToken.ownerOf(1);

        // Create array of token IDs
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        HomeReentrancyContract homeReentrancyContract = new HomeReentrancyContract(homeToken, remoteToken, homeNFT);

        // Send tokens with contract call
        bytes memory receiverPayload = abi.encode("test data");
        homeToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipientContract: address(remoteReceiver),
                recipientPayload: receiverPayload,
                recipientGasLimit: 800000,
                fallbackRecipient: user2,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 900000
            }),
            tokenIds
        );
        vm.stopPrank();

        // Check tokens are owned by home contract
        assertEq(homeNFT.ownerOf(1), address(homeToken), "Token 1 not owned by home contract");

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify tokens are owned by the receiver contract
        assertEq(remoteToken.ownerOf(1), address(remoteReceiver), "Token 1 not owned by receiver contract");

        // Send tokens back to home with contract call
        vm.prank(address(remoteReceiver));
        remoteToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipientContract: address(homeReentrancyContract),
                recipientPayload: receiverPayload,
                recipientGasLimit: 800000,
                fallbackRecipient: address(homeReentrancyContract),
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 900000
            }),
            tokenIds
        );

        // Process the return message(s)
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));
        if (teleporterMessenger.hasPendingMessages(REMOTE_CHAIN_ID, address(remoteToken))) {
            processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));
        }

        // Verify tokens are owned by the home receiver contract
        assertEq(homeNFT.ownerOf(1), address(homeReentrancyContract));

        // Check remote token state - should be burned
        vm.expectRevert();
        remoteToken.ownerOf(1);
    }
}
