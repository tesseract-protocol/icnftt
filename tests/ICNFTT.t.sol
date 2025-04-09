// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../contracts/ERC721TokenHome.sol";
import "../contracts/ERC721TokenRemote.sol";
import {
    TeleporterFeeInfo,
    TeleporterMessageInput,
    TeleporterMessage,
    TeleporterMessageReceipt
} from "@teleporter/ITeleporterMessenger.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    SendNFTInput,
    UpdateRemoteBaseURIMessage,
    TransferTokenMessage
} from "../contracts/interfaces/INFTTransferrer.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

// Mock of IWarpMessenger to return chain IDs
contract MockWarpMessenger {
    bytes32 private _blockchainID;

    constructor(
        bytes32 blockchainID
    ) {
        _blockchainID = blockchainID;
    }

    function getBlockchainID() external view returns (bytes32) {
        return _blockchainID;
    }
}

// Mock TeleporterRegistry to simulate the registry functionality
contract MockTeleporterRegistry {
    address private _owner;
    address private _latestTeleporter;

    constructor(
        address mockTeleporter
    ) {
        _owner = msg.sender;
        _latestTeleporter = mockTeleporter;
    }

    // Mock the necessary functions that our contracts will call
    function latestVersion() external pure returns (uint256) {
        return 1;
    }

    function getLatestTeleporter() external view returns (address) {
        return _latestTeleporter;
    }

    function getTeleporterAddress(
        uint256 version
    ) external view returns (address) {
        return _latestTeleporter;
    }

    function getVersionFromAddress(
        address
    ) external view returns (uint256) {
        return 1;
    }

    function getMinTeleporterVersion() external pure returns (uint256) {
        return 1;
    }
}

// Mock Teleporter to simulate cross-chain message passing
contract MockTeleporterMessenger {
    // Events defined in ITeleporterMessenger
    event SendCrossChainMessage(
        bytes32 indexed messageID,
        bytes32 indexed destinationBlockchainID,
        TeleporterMessage message,
        TeleporterFeeInfo feeInfo
    );

    event ReceiveCrossChainMessage(
        bytes32 indexed messageID,
        bytes32 indexed sourceBlockchainID,
        address indexed deliverer,
        address rewardRedeemer,
        TeleporterMessage message
    );

    bytes32 private _blockchainID;
    uint256 private _messageNonce;
    bytes32 public HOME_CHAIN_ID;
    bytes32 public REMOTE_CHAIN_ID;

    // Mapping to store pending messages
    mapping(bytes32 => mapping(address => bytes[])) private _pendingMessages;
    mapping(bytes32 => mapping(address => address[])) private _pendingSenders;
    mapping(bytes32 => mapping(address => bytes32[])) private _pendingSourceChains;
    mapping(bytes32 => mapping(address => uint256[])) private _pendingNonces;

    constructor(
        bytes32 blockchainID
    ) {
        _blockchainID = blockchainID;
        HOME_CHAIN_ID = blockchainID;
    }

    function setRemoteChainID(
        bytes32 remoteChainID
    ) external {
        REMOTE_CHAIN_ID = remoteChainID;
    }

    function getBlockchainID() external view returns (bytes32) {
        return _blockchainID;
    }

    // Match the ITeleporterMessenger interface
    function sendCrossChainMessage(
        TeleporterMessageInput calldata messageInput
    ) external returns (bytes32) {
        // Generate a message ID based on current nonce
        bytes32 messageID =
            keccak256(abi.encodePacked(_messageNonce, _blockchainID, messageInput.destinationBlockchainID));

        // Create the TeleporterMessage
        TeleporterMessage memory message = TeleporterMessage({
            messageNonce: _messageNonce,
            originSenderAddress: msg.sender,
            destinationBlockchainID: messageInput.destinationBlockchainID,
            destinationAddress: messageInput.destinationAddress,
            requiredGasLimit: messageInput.requiredGasLimit,
            allowedRelayerAddresses: messageInput.allowedRelayerAddresses,
            receipts: new TeleporterMessageReceipt[](0),
            message: messageInput.message
        });

        // Store the message for later delivery
        _pendingMessages[messageInput.destinationBlockchainID][messageInput.destinationAddress].push(
            messageInput.message
        );
        _pendingSenders[messageInput.destinationBlockchainID][messageInput.destinationAddress].push(msg.sender);
        _pendingSourceChains[messageInput.destinationBlockchainID][messageInput.destinationAddress].push(_blockchainID);
        _pendingNonces[messageInput.destinationBlockchainID][messageInput.destinationAddress].push(_messageNonce);

        // Increment nonce for next message
        _messageNonce++;

        // Emit event for tracking
        emit SendCrossChainMessage(messageID, messageInput.destinationBlockchainID, message, messageInput.feeInfo);

        return messageID;
    }

    // Deliver a pending message to its destination
    function deliverNextMessage(bytes32 destinationChainID, address destinationAddress) external returns (bool) {
        bytes[] storage messages = _pendingMessages[destinationChainID][destinationAddress];
        address[] storage senders = _pendingSenders[destinationChainID][destinationAddress];
        bytes32[] storage sourceChains = _pendingSourceChains[destinationChainID][destinationAddress];
        uint256[] storage nonces = _pendingNonces[destinationChainID][destinationAddress];

        require(messages.length > 0, "No pending messages");

        // Get the oldest message
        bytes memory message = messages[0];
        address sender = senders[0];
        bytes32 sourceChain = sourceChains[0];
        uint256 nonce = nonces[0];

        // Remove it from all queues
        for (uint i = 0; i < messages.length - 1; i++) {
            messages[i] = messages[i + 1];
            senders[i] = senders[i + 1];
            sourceChains[i] = sourceChains[i + 1];
            nonces[i] = nonces[i + 1];
        }
        messages.pop();
        senders.pop();
        sourceChains.pop();
        nonces.pop();

        // Create message ID and message struct for the event
        bytes32 messageID = keccak256(abi.encodePacked(nonce, sourceChain, destinationChainID));
        TeleporterMessage memory teleporterMessage = TeleporterMessage({
            messageNonce: nonce,
            originSenderAddress: sender,
            destinationBlockchainID: destinationChainID,
            destinationAddress: destinationAddress,
            requiredGasLimit: 200000, // Default value
            allowedRelayerAddresses: new address[](0),
            receipts: new TeleporterMessageReceipt[](0),
            message: message
        });

        // Emit receive event
        emit ReceiveCrossChainMessage(
            messageID,
            sourceChain,
            msg.sender, // deliverer
            msg.sender, // reward redeemer
            teleporterMessage
        );

        // Figure out the correct source chain to pass to the receiver
        // For registration messages, if the source is a remote contract, use REMOTE_CHAIN_ID
        bytes32 effectiveSourceChain = sourceChain;

        // If we're at the home contract and message is a registration, we need to override the source chain
        if (destinationAddress == address(ICNFTT_Test(msg.sender).homeToken())) {
            // Try to decode the message as a TransferrerMessage
            try this.decodeMessage(message) returns (TransferrerMessageType messageType) {
                if (messageType == TransferrerMessageType.REGISTER_REMOTE) {
                    // For registration messages, use REMOTE_CHAIN_ID
                    effectiveSourceChain = REMOTE_CHAIN_ID;
                }
            } catch {
                // If decoding fails, continue with the original sourceChain
            }
        }

        // Call the destination contract's receive function
        (bool success,) = destinationAddress.call(
            abi.encodeWithSignature(
                "receiveTeleporterMessage(bytes32,address,bytes)", effectiveSourceChain, sender, message
            )
        );

        return success;
    }

    // Helper function to decode the message type
    function decodeMessage(
        bytes memory message
    ) external pure returns (TransferrerMessageType) {
        TransferrerMessage memory transferrerMessage = abi.decode(message, (TransferrerMessage));
        return transferrerMessage.messageType;
    }

    // Check if there are pending messages
    function hasPendingMessages(bytes32 destinationChainID, address destinationAddress) external view returns (bool) {
        return _pendingMessages[destinationChainID][destinationAddress].length > 0;
    }

    // Get count of pending messages
    function getPendingMessageCount(
        bytes32 destinationChainID,
        address destinationAddress
    ) external view returns (uint256) {
        return _pendingMessages[destinationChainID][destinationAddress].length;
    }
}

contract ICNFTT_Test is Test {
    // Contracts under test
    ERC721TokenHome public homeToken;
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

    function setUp() public {
        // Setup the mock teleporter messenger with home chain ID
        teleporterMessenger = new MockTeleporterMessenger(HOME_CHAIN_ID);
        teleporterMessenger.setRemoteChainID(REMOTE_CHAIN_ID);

        // Setup the mock teleporter registry that points to our messenger
        teleporterRegistry = new MockTeleporterRegistry(address(teleporterMessenger));

        // Deploy mock warp messenger for home chain
        MockWarpMessenger homeMockWarp = new MockWarpMessenger(HOME_CHAIN_ID);
        vm.etch(WARP_PRECOMPILE, address(homeMockWarp).code);

        // Setup home token contract
        vm.startPrank(owner);
        homeToken = new ERC721TokenHome(
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
        vm.startPrank(owner);
        remoteToken.registerWithHome(TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));
        vm.stopPrank();

        // Deliver the register message from remote to home
        processNextTeleporterMessage(HOME_CHAIN_ID, address(homeToken));
    }

    // Test remote chain registration process
    function testRegisterRemote() public {
        // Start with no registered chains
        bytes32[] memory initialChains = homeToken.getRegisteredChains();
        assertEq(initialChains.length, 0);

        // Register remote with home
        vm.startPrank(owner);
        remoteToken.registerWithHome(TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}));
        vm.stopPrank();

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

        // Mint a token on home
        vm.startPrank(owner);
        homeToken.mint(user1, 1, "token1.json");
        vm.stopPrank();

        // User sends token to remote chain
        vm.startPrank(user1);
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
        vm.stopPrank();

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

        // Mint a token on home
        vm.startPrank(owner);
        homeToken.mint(user1, 1, "token1.json");
        vm.stopPrank();

        // User sends token to remote chain
        vm.startPrank(user1);
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
        vm.stopPrank();

        // Process the message at remote
        processNextTeleporterMessage(REMOTE_CHAIN_ID, address(remoteToken));

        // Now user sends token back from remote to home
        vm.startPrank(user1);
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
        vm.stopPrank();

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
}
