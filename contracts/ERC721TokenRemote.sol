// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorage, ERC721} from "./ERC721URIStorage.sol";
import {IERC721TokenRemote} from "./interfaces/IERC721TokenRemote.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    SendTokenMessage,
    SendTokenInput,
    SendAndCallInput,
    TokenSent,
    TokenAndCallSent,
    IERC721Transferrer,
    UpdateRemoteBaseURIMessage,
    UpdateRemoteTokenURIMessage,
    SendAndCallMessage,
    CallSucceeded,
    CallFailed
} from "./interfaces/IERC721Transferrer.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CallUtils} from "@utilities/CallUtils.sol";
import {IERC721SendAndCallReceiver} from "./interfaces/IERC721SendAndCallReceiver.sol";

contract ERC721TokenRemote is IERC721TokenRemote, IERC721Transferrer, ERC721URIStorage, TeleporterRegistryOwnableApp {
    bytes32 internal immutable _homeChainId;
    address internal immutable _homeContractAddress;
    bytes32 internal immutable _blockchainID;
    uint256 public constant REGISTER_REMOTE_REQUIRED_GAS = 130_000;

    bool internal _isRegistered;
    string internal _baseURIStorage;

    constructor(
        string memory name,
        string memory symbol,
        bytes32 homeChainId_,
        address homeContractAddress_,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    ) ERC721(name, symbol) TeleporterRegistryOwnableApp(teleporterRegistryAddress, msg.sender, minTeleporterVersion) {
        require(homeChainId_ != bytes32(0), "ERC721TokenRemote: zero home blockchain ID");
        require(homeContractAddress_ != address(0), "ERC721TokenRemote: zero home contract address");

        _homeChainId = homeChainId_;
        _homeContractAddress = homeContractAddress_;
        _blockchainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();

        emit HomeChainRegistered(_homeChainId, _homeContractAddress);
    }

    function getHomeChainId() external view override returns (bytes32) {
        return _homeChainId;
    }

    function getHomeTokenAddress() external view override returns (address) {
        return _homeContractAddress;
    }

    function getBlockchainID() external view returns (bytes32) {
        return _blockchainID;
    }

    function getIsRegistered() external view returns (bool) {
        return _isRegistered;
    }

    function send(SendTokenInput calldata input, uint256 tokenId) external override {
        require(input.destinationBlockchainID == _homeChainId, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(
                SendTokenMessage({recipient: input.recipient, tokenId: tokenId, tokenURI: _tokenURIs[tokenId]})
            )
        });

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);

        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationTokenTransferrerAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );

        _burn(tokenId);

        emit TokenBurned(tokenId, tokenOwner);
        emit TokenSent(messageID, msg.sender, tokenId);
    }

    /**
     * @notice Sends a token to a contract on the home chain and calls a function on it
     * @param input The parameters for the cross-chain call
     * @param tokenId The ID of the token to send
     */
    function sendAndCall(SendAndCallInput calldata input, uint256 tokenId) external override {
        require(input.destinationBlockchainID == _homeChainId, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");
        require(input.recipientContract != address(0), "ERC721TokenRemote: zero recipient contract address");
        require(input.fallbackRecipient != address(0), "ERC721TokenRemote: zero fallback recipient address");
        require(input.requiredGasLimit > 0, "ERC721TokenRemote: zero required gas limit");
        require(input.recipientGasLimit > 0, "ERC721TokenRemote: zero recipient gas limit");
        require(input.recipientGasLimit < input.requiredGasLimit, "ERC721TokenRemote: recipient gas limit too high");

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        SendAndCallMessage memory callMessage = SendAndCallMessage({
            recipientContract: input.recipientContract,
            tokenId: tokenId,
            tokenURI: _tokenURIs[tokenId],
            originSenderAddress: msg.sender,
            recipientPayload: input.recipientPayload,
            recipientGasLimit: input.recipientGasLimit,
            fallbackRecipient: input.fallbackRecipient
        });

        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.SINGLE_HOP_CALL, payload: abi.encode(callMessage)});

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);

        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationTokenTransferrerAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );

        _burn(tokenId);

        emit TokenBurned(tokenId, tokenOwner);
        emit TokenAndCallSent(messageID, msg.sender, tokenId);
    }

    function _receiveToken(uint256 tokenId, address recipient, string memory tokenURI) internal {
        _mint(recipient, tokenId);
        _setTokenURI(tokenId, tokenURI);
        emit TokenMinted(tokenId, recipient);
    }

    /**
     * @dev Processes a send and call message by minting the NFT and calling the recipient contract.
     * This is the ERC721 version of the send and call mechanism from ERC20TokenRemoteUpgradeable.
     * @param message The send and call message including recipient calldata
     * @param tokenId The token ID to be sent to the recipient
     */
    function _handleSendAndCall(SendAndCallMessage memory message, uint256 tokenId) internal {
        _mint(address(this), tokenId);
        _setTokenURI(tokenId, message.tokenURI);

        approve(message.recipientContract, tokenId);

        bytes memory payload = abi.encodeCall(
            IERC721SendAndCallReceiver.receiveToken,
            (
                _homeChainId,
                _homeContractAddress,
                message.originSenderAddress,
                address(this),
                tokenId,
                message.recipientPayload
            )
        );

        bool success = CallUtils._callWithExactGas(message.recipientGasLimit, message.recipientContract, payload);

        if (success) {
            emit CallSucceeded(message.recipientContract, tokenId);

            if (ownerOf(tokenId) == address(this)) {
                approve(address(0), tokenId);
                _safeTransfer(address(this), message.fallbackRecipient, tokenId, "");
            }
        } else {
            emit CallFailed(message.recipientContract, tokenId);
            approve(address(0), tokenId);
            _safeTransfer(address(this), message.fallbackRecipient, tokenId, "");
        }
    }

    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override {
        require(sourceBlockchainID == _homeChainId, "ERC721TokenRemote: invalid source blockchain");
        require(originSenderAddress == _homeContractAddress, "ERC721TokenRemote: invalid origin sender");

        TransferrerMessage memory transferrerMessage = abi.decode(message, (TransferrerMessage));

        if (!_isRegistered) {
            _isRegistered = true;
        }

        if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_SEND) {
            SendTokenMessage memory sendTokenMessage = abi.decode(transferrerMessage.payload, (SendTokenMessage));
            _receiveToken(sendTokenMessage.tokenId, sendTokenMessage.recipient, sendTokenMessage.tokenURI);
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_CALL) {
            SendAndCallMessage memory callMessage = abi.decode(transferrerMessage.payload, (SendAndCallMessage));
            _handleSendAndCall(callMessage, callMessage.tokenId);
        } else if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_REMOTE_BASE_URI) {
            UpdateRemoteBaseURIMessage memory updateRemoteBaseURIMessage =
                abi.decode(transferrerMessage.payload, (UpdateRemoteBaseURIMessage));
            _baseURIStorage = updateRemoteBaseURIMessage.baseURI;
            emit RemoteBaseURIUpdated(_baseURIStorage);
        } else if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_REMOTE_TOKEN_URI) {
            UpdateRemoteTokenURIMessage memory updateRemoteTokenURIMessage =
                abi.decode(transferrerMessage.payload, (UpdateRemoteTokenURIMessage));
            _setTokenURI(updateRemoteTokenURIMessage.tokenId, updateRemoteTokenURIMessage.uri);
            emit RemoteTokenURIUpdated(updateRemoteTokenURIMessage.tokenId, updateRemoteTokenURIMessage.uri);
        }
    }

    function registerWithHome(
        TeleporterFeeInfo calldata feeInfo
    ) external virtual {
        require(!_isRegistered, "ERC721TokenRemote: already registered");

        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.REGISTER_REMOTE, payload: bytes("")});

        _handleFees(feeInfo.feeTokenAddress, feeInfo.amount);

        _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: _homeChainId,
                destinationAddress: _homeContractAddress,
                feeInfo: feeInfo,
                requiredGasLimit: REGISTER_REMOTE_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );
    }

    function _handleFees(address feeTokenAddress, uint256 feeAmount) internal returns (uint256) {
        if (feeAmount == 0) {
            return 0;
        }
        return SafeERC20TransferFrom.safeTransferFrom(IERC20(feeTokenAddress), _msgSender(), feeAmount);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseURIStorage;
    }
}
