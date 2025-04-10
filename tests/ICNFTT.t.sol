// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../contracts/ERC721TokenHome.sol";
import "../contracts/ERC721TokenRemote.sol";
import {SendNFTInput} from "../contracts/interfaces/INFTTransferrer.sol";
import {MockTeleporterMessenger, MockTeleporterRegistry, MockWarpMessenger} from "./Mocks.sol";

contract ERC721TokenHomePublicMint is ERC721TokenHome {
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    ) ERC721TokenHome(name, symbol, baseURI, teleporterRegistryAddress, minTeleporterVersion) {}

    function mint(address to, uint256 tokenId, string memory tokenURI) external {
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }
}

contract ICNFTT_Test is Test {
    // Contracts under test
    ERC721TokenHomePublicMint public homeToken;
    ERC721TokenRemote public remoteToken;

    // Mock contracts
    MockTeleporterMessenger teleporterMessenger;
    MockTeleporterRegistry teleporterRegistry;

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

        // Setup home token contract
        vm.startPrank(owner);
        homeToken = new ERC721TokenHomePublicMint(
            "HomeNFT",
            "HNFT",
            "https://home.nft/",
            address(teleporterRegistry),
            1 // minTeleporterVersion
        );
        vm.stopPrank();

        // Change the mock warp messenger for remote chain
        MockWarpMessenger remoteMockWarp = new MockWarpMessenger(REMOTE_CHAIN_ID);
        vm.etch(WARP_PRECOMPILE, address(remoteMockWarp).code);

        // Setup remote token contract
        vm.startPrank(owner);
        remoteToken = new ERC721TokenRemote(
            "RemoteNFT",
            "RNFT",
            HOME_CHAIN_ID,
            address(homeToken),
            address(teleporterRegistry),
            1 // minTeleporterVersion
        );
        vm.stopPrank();
    }

    // Helper function to process teleporter messages
    function processNextTeleporterMessage(bytes32 destinationChainID, address destinationAddress) internal {
        require(teleporterMessenger.hasPendingMessages(destinationChainID, destinationAddress), "No pending messages");
        bool success = teleporterMessenger.deliverNextMessage(destinationChainID, destinationAddress);
        require(success, "Message delivery failed");
    }

    // Helper function to register remote chain with home
    function _registerRemoteChain() internal {
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

    // Test sending token from home to remote
    function testSendTokenFromHomeToRemote() public {
        // First register the remote chain with the home contract
        _registerRemoteChain();

        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // User sends token to remote chain
        vm.prank(user1);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Check token is now owned by the home contract instead of being locked
        assertEq(homeToken.ownerOf(1), address(homeToken));

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

        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // User sends token to remote chain
        vm.prank(user1);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Now user sends token back from remote to home
        vm.prank(user1);
        remoteToken.send(
            SendNFTInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Verify token is burned on remote
        vm.expectRevert();
        remoteToken.ownerOf(1);

        // Verify message was sent from remote to home
        assertTrue(teleporterMessenger.hasPendingMessages(HOME_CHAIN_ID, address(homeToken)));

        // Process the message at home
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify token is transferred back to user1 (instead of being unlocked)
        assertEq(homeToken.ownerOf(1), user1);
    }

    // Test token-specific approval to send token to remote chain
    function testSendWithTokenSpecificApproval() public {
        _registerRemoteChain();

        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // User1 approves operator for the specific tokenId
        vm.prank(user1);
        homeToken.approve(operator, 1);

        // Operator sends token to remote chain on behalf of user1
        vm.prank(operator);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1, // Still sending to user1
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Verify token ownership transferred to home contract
        assertEq(homeToken.ownerOf(1), address(homeToken));

        // Process the message to remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify token minted on remote chain to user1
        assertEq(remoteToken.ownerOf(1), user1);
    }

    // Test approval for all tokens to send to remote chain
    function testSendWithApprovalForAll() public {
        _registerRemoteChain();

        // User1 mints two tokens
        vm.startPrank(user1);
        homeToken.mint(user1, 1, "token1.json");
        homeToken.mint(user1, 2, "token2.json");

        // User1 approves operator for all tokens
        homeToken.setApprovalForAll(operator, true);
        vm.stopPrank();

        // Operator sends first token to remote chain
        vm.prank(operator);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Operator sends second token to remote chain
        vm.prank(operator);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user2, // Sending to different recipient
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            2 // tokenId
        );

        // Process messages to remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify tokens minted on remote chain to correct recipients
        assertEq(remoteToken.ownerOf(1), user1);
        assertEq(remoteToken.ownerOf(2), user2);
    }

    // Test sending to different recipient on remote chain
    function testSendToDifferentRecipient() public {
        _registerRemoteChain();

        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // User1 sends token to user2 on remote chain
        vm.prank(user1);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user2, // Different recipient
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Process the message
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify token minted to user2 on remote chain
        assertEq(remoteToken.ownerOf(1), user2);
    }

    // Test sending token to unregistered chain
    function testSendToUnregisteredChainFails() public {
        // Don't register the remote chain

        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // User attempts to send to unregistered chain - should revert
        vm.expectRevert("ERC721TokenHome: destination chain not registered");
        vm.prank(user1);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );
    }

    // Test updating baseURI and confirming it applies to tokens
    function testUpdateBaseURI() public {
        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // Owner updates baseURI
        vm.prank(owner);
        string memory newBaseURI = "https://updated.nft/";
        homeToken.updateBaseURI(newBaseURI);

        // Verify the token URI reflects the updated baseURI
        string memory expectedURI = string.concat(newBaseURI, "token1.json");
        assertEq(homeToken.tokenURI(1), expectedURI);
    }

    // Test non-owner cannot update baseURI
    function testNonOwnerCannotUpdateBaseURI() public {
        vm.expectRevert(); // Should revert with onlyOwner error
        vm.prank(user1);
        homeToken.updateBaseURI("https://hacker.nft/");
    }

    // Test transferring to recipient that doesn't exist on remote
    function testRoundTripToNewRecipient() public {
        _registerRemoteChain();

        // User1 mints a token directly
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // User1 sends token to user2 on remote chain
        vm.prank(user1);
        homeToken.send(
            SendNFTInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user2,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Process the message
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // User2 sends token back to a new recipient on home
        vm.prank(user2);
        remoteToken.send(
            SendNFTInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipient: operator, // New recipient who hasn't interacted before
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Process the return message
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify token is now owned by the new recipient on home
        assertEq(homeToken.ownerOf(1), operator);
    }

    // Test multiple users minting tokens
    function testMultipleUsersMintingTokens() public {
        // Multiple users mint tokens
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        vm.prank(user2);
        homeToken.mint(user2, 2, "token2.json");

        vm.prank(operator);
        homeToken.mint(operator, 3, "token3.json");

        // Verify ownership
        assertEq(homeToken.ownerOf(1), user1);
        assertEq(homeToken.ownerOf(2), user2);
        assertEq(homeToken.ownerOf(3), operator);
    }
}
