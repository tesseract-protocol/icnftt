// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorage, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC721TokenRemote} from "./interfaces/IERC721TokenRemote.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    TransferTokenMessage,
    SendNFTInput,
    TokenSent,
    INFTTransferrer,
    UpdateRemoteBaseURIMessage
} from "./interfaces/INFTTransferrer.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC721TokenRemote is IERC721TokenRemote, INFTTransferrer, ERC721URIStorage, TeleporterRegistryOwnableApp {
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

    function _baseURI() internal view override returns (string memory) {
        return _baseURIStorage;
    }

    function send(SendNFTInput calldata input, uint256 tokenId) external override {
        _validateSend(input, tokenId);

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(TransferTokenMessage({recipient: input.recipient, tokenId: tokenId}))
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

        emit TokenBurned(tokenId, input.recipient);
        emit TokenSent(messageID, msg.sender, tokenId);
    }

    function receiveToken(uint256 tokenId, address recipient) internal {
        _mint(recipient, tokenId);
        emit TokenMinted(tokenId, recipient);
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
            TransferTokenMessage memory transferTokenMessage =
                abi.decode(transferrerMessage.payload, (TransferTokenMessage));

            receiveToken(transferTokenMessage.tokenId, transferTokenMessage.recipient);
        } else if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_REMOTE_BASE_URI) {
            UpdateRemoteBaseURIMessage memory updateRemoteBaseURIMessage =
                abi.decode(transferrerMessage.payload, (UpdateRemoteBaseURIMessage));
            _baseURIStorage = updateRemoteBaseURIMessage.baseURI;
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

    function _validateSend(SendNFTInput calldata input, uint256 tokenId) internal view {
        require(_exists(tokenId), "ERC721TokenRemote: token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender)
                || getApproved(tokenId) == msg.sender,
            "ERC721TokenRemote: not owner or approved"
        );
        require(input.destinationBlockchainID == _homeChainId, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");
    }

    // Helper function to check if token exists
    function _exists(
        uint256 tokenId
    ) internal view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
