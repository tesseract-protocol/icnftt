// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/TokenHome/ERC721TokenHome.sol";
import "../contracts/TokenHome/extensions/ERC721URIStorageHomeExtension.sol";
import "../contracts/TokenRemote/ERC721TokenRemote.sol";
import "../contracts/TokenRemote/extensions/ERC721URIStorageRemoteExtension.sol";
import {SendTokenInput, SendAndCallInput} from "../contracts/interfaces/IERC721Transferrer.sol";
import {MockTeleporterMessenger, MockTeleporterRegistry, MockWarpMessenger, MockERC721Receiver} from "./Mocks.sol";

contract ERC721TokenHomePublicMint is ERC721TokenHome, ERC721URIStorageHomeExtension {
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    ) ERC721TokenHome(name, symbol, baseURI, teleporterRegistryAddress, minTeleporterVersion) {}

    function mint(address to, uint256 tokenId, string memory _tokenURI) external {
        _mint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
    }

    function _updateExtensions(uint256 tokenId, ExtensionMessage[] memory extensions) internal override {
        for (uint256 i = 0; i < extensions.length; i++) {
            if (extensions[i].key == ERC4906_INTERFACE_ID) {
                ERC721URIStorageExtension._update(tokenId, extensions[i]);
            }
        }
    }

    function _getExtensionMessages(
        uint256 tokenId
    ) internal view override returns (ExtensionMessage[] memory) {
        ExtensionMessage[] memory extensionMessages = new ExtensionMessage[](1);
        extensionMessages[0] = ERC721URIStorageExtension._getMessage(tokenId);
        return extensionMessages;
    }

    function _baseURI()
        internal
        view
        override (ERC721URIStorageHomeExtension, ERC721TokenHome)
        returns (string memory)
    {
        return super._baseURI();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override (ERC721URIStorageHomeExtension, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override (ERC721URIStorageHomeExtension, ERC721TokenHome) {
        super._receiveTeleporterMessage(sourceBlockchainID, originSenderAddress, message);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override (ERC721URIStorageHomeExtension, ERC721) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}

contract TokenRemote is ERC721TokenRemote, ERC721URIStorageRemoteExtension {
    constructor(
        string memory name,
        string memory symbol,
        bytes32 homeChainId,
        address homeTokenAddress,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    ) ERC721TokenRemote(name, symbol, homeChainId, homeTokenAddress, teleporterRegistryAddress, minTeleporterVersion) {}

    function _updateExtensions(uint256 tokenId, ExtensionMessage[] memory extensions) internal override {
        for (uint256 i = 0; i < extensions.length; i++) {
            if (extensions[i].key == ERC4906_INTERFACE_ID) {
                ERC721URIStorageExtension._update(tokenId, extensions[i]);
            }
        }
    }

    function _getExtensionMessages(
        uint256 tokenId
    ) internal view override returns (ExtensionMessage[] memory) {
        ExtensionMessage[] memory extensionMessages = new ExtensionMessage[](1);
        extensionMessages[0] = ERC721URIStorageExtension._getMessage(tokenId);
        return extensionMessages;
    }

    function _baseURI()
        internal
        view
        override (ERC721URIStorageRemoteExtension, ERC721TokenRemote)
        returns (string memory)
    {
        return super._baseURI();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override (ERC721URIStorageRemoteExtension, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override (ERC721URIStorageRemoteExtension, ERC721TokenRemote) {
        super._receiveTeleporterMessage(sourceBlockchainID, originSenderAddress, message);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override (ERC721URIStorageRemoteExtension, ERC721) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}

contract ICNFTT_Test is Test {
    // Contracts under test
    ERC721TokenHomePublicMint public homeToken;
    ERC721TokenRemote public remoteToken;

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
        remoteToken = new TokenRemote(
            "RemoteNFT",
            "RNFT",
            HOME_CHAIN_ID,
            address(homeToken),
            address(teleporterRegistry),
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

    // Helper function to register remote chain with home and sync the baseURI
    function _registerRemoteChainAndSyncBaseURI() internal {
        // Register remote chain with home
        _registerRemoteChain();

        // Update baseURI on remote
        vm.prank(owner);
        homeToken.updateBaseURI(
            "https://home.nft/",
            true, // propagate to remote chains
            TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0})
        );

        // Process the baseURI update message
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));
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
            SendTokenInput({
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
            SendTokenInput({
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
            SendTokenInput({
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
            SendTokenInput({
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
            SendTokenInput({
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
            SendTokenInput({
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
            SendTokenInput({
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
            SendTokenInput({
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
        homeToken.updateBaseURI(newBaseURI, false, TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));

        // Verify the token URI reflects the updated baseURI
        string memory expectedURI = string.concat(newBaseURI, "token1.json");
        assertEq(homeToken.tokenURI(1), expectedURI);
    }

    // Test non-owner cannot update baseURI
    function testNonOwnerCannotUpdateBaseURI() public {
        vm.expectRevert(); // Should revert with onlyOwner error
        vm.prank(user1);
        homeToken.updateBaseURI(
            "https://hacker.nft/", false, TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0})
        );
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
            SendTokenInput({
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
            SendTokenInput({
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

    // Test updating a token's URI locally only
    function testUpdateTokenURILocally() public {
        // User1 mints a token
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // Initial URI should combine baseURI and token URI
        string memory initialURI = string.concat("https://home.nft/", "token1.json");
        assertEq(homeToken.tokenURI(1), initialURI);

        // Owner updates just the token URI without updating remote
        vm.prank(owner);
        homeToken.updateTokenURI(
            1,
            "updated-token1.json",
            false, // don't update remote
            TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0})
        );

        // Verify the token URI was updated locally
        string memory updatedURI = string.concat("https://home.nft/", "updated-token1.json");
        assertEq(homeToken.tokenURI(1), updatedURI);
    }

    // Test updating a token's URI on both home and remote
    function testUpdateTokenURIOnRemote() public {
        // First register the remote chain and sync baseURI
        _registerRemoteChainAndSyncBaseURI();

        // User1 mints a token
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // Send the token to remote chain
        vm.prank(user1);
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Process the message to get the token on remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify initial URI on remote
        string memory initialRemoteURI = string.concat("https://home.nft/", "token1.json");
        assertEq(remoteToken.tokenURI(1), initialRemoteURI);

        // Owner updates the token URI and propagates to remote
        vm.prank(owner);
        homeToken.updateTokenURI(
            1,
            "updated-token1.json",
            true, // update remote
            TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0})
        );

        // Process the message to update URI on remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify the token URI was updated on the remote
        string memory updatedRemoteURI = string.concat("https://home.nft/", "updated-token1.json");
        assertEq(remoteToken.tokenURI(1), updatedRemoteURI);
    }

    // Test that token URI is preserved when sending to remote
    function testTokenURIPreservedWhenSendingToRemote() public {
        _registerRemoteChainAndSyncBaseURI();

        // User1 mints a token with a custom URI
        vm.prank(user1);
        homeToken.mint(user1, 1, "special-token.json");

        // Verify initial URI on home
        string memory initialHomeURI = string.concat("https://home.nft/", "special-token.json");
        assertEq(homeToken.tokenURI(1), initialHomeURI);

        // Send token to remote
        vm.prank(user1);
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

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
            1 // tokenId
        );

        // Process the return message
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify the token URI is still preserved after round trip
        assertEq(homeToken.tokenURI(1), initialHomeURI);
    }

    // Test sending a token from Home to Remote with sendAndCall
    function testSendAndCallFromHome() public {
        // First register the remote chain and sync baseURI
        _registerRemoteChainAndSyncBaseURI();

        // User1 mints a token
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // Create a simple payload for the test
        bytes memory testPayload = hex"01";

        // User1 sends token to receiver contract on remote chain with sendAndCall
        vm.prank(user1);
        homeToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipientContract: address(remoteReceiver),
                fallbackRecipient: user1, // Original owner as fallback
                recipientPayload: testPayload,
                recipientGasLimit: 300000,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 600000
            }),
            1 // tokenId
        );

        // Process the message to get the token on remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify the payload was correctly received
        assertEq(remoteReceiver.lastPayload(), testPayload, "Payload should be correct");

        // Verify the token is owned by the recipient contract
        assertEq(remoteToken.ownerOf(1), address(remoteReceiver), "Token should be owned by the recipient contract");

        // Verify the last received token has the correct sourceBlockchainID
        (bytes32 sourceChain,,,,,) = remoteReceiver.lastReceivedToken();
        assertEq(sourceChain, HOME_CHAIN_ID, "Source chain should be correct");
    }

    // Test sendAndCall with fallback recipient case
    function testSendAndCallFromHomeWithFallback() public {
        // First register the remote chain and sync baseURI
        _registerRemoteChainAndSyncBaseURI();

        // User1 mints a token
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // Create a simple payload for the test
        bytes memory testPayload = hex"00";

        // User1 sends token to receiver contract on remote chain with sendAndCall
        // but with a non-existent recipientContract (zero address) to trigger fallback
        vm.prank(user1);
        homeToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipientContract: address(remoteReceiver), // Invalid recipient to trigger fallback
                fallbackRecipient: user1, // Original owner as fallback
                recipientPayload: testPayload,
                recipientGasLimit: 100000,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 300000
            }),
            1 // tokenId
        );

        // Process the message to get the token on remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify the token was transferred to the fallback recipient
        assertEq(remoteToken.ownerOf(1), user1);

        // The receiver should not have been called
        assertEq(remoteReceiver.receiveCount(), 0);
    }

    // Test sending a token from Remote to Home with sendAndCall
    function testSendAndCallFromRemote() public {
        // First register the remote chain, sync baseURI, and get a token to remote
        _registerRemoteChainAndSyncBaseURI();

        // User1 mints a token
        vm.prank(user1);
        homeToken.mint(user1, 1, "token1.json");

        // Send the token to remote chain
        vm.prank(user1);
        homeToken.send(
            SendTokenInput({
                destinationBlockchainID: REMOTE_CHAIN_ID,
                destinationTokenTransferrerAddress: address(remoteToken),
                recipient: user1,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 200000
            }),
            1 // tokenId
        );

        // Process the message to get the token on remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Verify token exists on remote chain owned by user1
        assertEq(remoteToken.ownerOf(1), user1);

        // Create a simple payload for the test
        bytes memory testPayload = hex"01";

        // User1 sends token from remote to home receiver with sendAndCall
        vm.prank(user1);
        remoteToken.sendAndCall(
            SendAndCallInput({
                destinationBlockchainID: HOME_CHAIN_ID,
                destinationTokenTransferrerAddress: address(homeToken),
                recipientContract: address(homeReceiver),
                fallbackRecipient: user1, // Original owner as fallback
                recipientPayload: testPayload,
                recipientGasLimit: 300000,
                primaryFeeTokenAddress: address(0),
                primaryFee: 0,
                requiredGasLimit: 600000
            }),
            1 // tokenId
        );

        // Process the message to get the token back to home
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));

        // Verify the token is owned by the receiver contract
        assertEq(homeToken.ownerOf(1), address(homeReceiver), "Token should be owned by the receiver contract");

        // Verify the payload was correctly received
        assertEq(homeReceiver.lastPayload(), testPayload, "Payload should be correct");

        // Check the recorded details
        (bytes32 sourceChain,,,,,) = homeReceiver.lastReceivedToken();
        assertEq(sourceChain, REMOTE_CHAIN_ID, "Source chain should be correct");
    }
}
