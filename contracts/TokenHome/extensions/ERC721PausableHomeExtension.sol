// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721PausableExtension} from "../../extensions/ERC721PausableExtension.sol";
import {ERC721TokenHome} from "../ERC721TokenHome.sol";
import {ERC721TokenTransferrer} from "../../ERC721TokenTransferrer.sol";
import {TransferrerMessage, TransferrerMessageType, ExtensionMessage} from "../../interfaces/IERC721Transferrer.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {
    PausableExtensionMessage,
    UpdatePausedStateInput,
    UpdateRemotePausedState
} from "../../extensions/interfaces/IERC721PausableExtension.sol";

/**
 * @title ERC721PausableHomeExtension
 * @dev An extension of ERC721TokenHome that adds pausable functionality for NFT transfers.
 *
 * This contract provides the ability to pause token transfers both locally and across
 * registered remote chains. When paused, token transfers are prevented (except when
 * the token is being held by this contract itself).
 *
 * Key features:
 * 1. Pause/unpause token transfers on the home chain
 * 2. Propagate pause states to all registered remote chains
 * 3. Selectively update pause state on specific remote chains
 * 4. Allow tokens in transit (owned by this contract) to complete their journey even when paused
 *
 * @dev This extension should be inherited instead of ERC721TokenHome if pausable
 * functionality is needed for your token contract
 */
abstract contract ERC721PausableHomeExtension is ERC721PausableExtension, ERC721TokenHome {
    /// @notice Gas limit for updating pause state on remote chains
    uint256 public constant UPDATE_PAUSE_STATE_GAS_LIMIT = 130_000;

    function _beforeTokenTransfer(address, uint256 tokenId) internal virtual override {
        if (_ownerOf(tokenId) != address(this)) {
            _requireNotPaused();
        }
    }

    /**
     * @notice Pauses token transfers and optionally updates pause state on remote chains
     * @dev Only callable by the owner
     * @param updateRemotes Whether to update the pause state on all registered remote chains
     * @param feeInfo Information about the fee to pay for cross-chain messages (if updating remotes)
     */
    function pause(bool updateRemotes, TeleporterFeeInfo memory feeInfo) external onlyOwner {
        _pause();

        if (updateRemotes) {
            _handleFees(feeInfo.feeTokenAddress, feeInfo.amount * _registeredChains.length);
            _pauseRemotes(feeInfo);
        }
    }

    /**
     * @notice Unpauses token transfers and optionally updates pause state on remote chains
     * @dev Only callable by the owner
     * @param updateRemotes Whether to update the pause state on all registered remote chains
     * @param feeInfo Information about the fee to pay for cross-chain messages (if updating remotes)
     */
    function unpause(bool updateRemotes, TeleporterFeeInfo memory feeInfo) external onlyOwner {
        _unpause();

        if (updateRemotes) {
            _handleFees(feeInfo.feeTokenAddress, feeInfo.amount * _registeredChains.length);
            _unpauseRemotes(feeInfo);
        }
    }

    /**
     * @notice Updates the pause state on a specific remote chain
     * @dev Only callable by the owner
     * @param input Parameters for the cross-chain pause state update
     * @param pauseState The pause state to set on the remote chain
     */
    function updateRemotePausedState(UpdatePausedStateInput calldata input, bool pauseState) external onlyOwner {
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);

        _updateRemotePausedState(
            input.destinationBlockchainID,
            remoteContract,
            pauseState,
            TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee})
        );
    }

    /**
     * @notice Internal function to pause all remote contracts
     * @param feeInfo Information about the fee to pay for cross-chain messages
     */
    function _pauseRemotes(
        TeleporterFeeInfo memory feeInfo
    ) internal {
        for (uint256 i = 0; i < _registeredChains.length; i++) {
            bytes32 remoteBlockchainID = _registeredChains[i];
            address remoteContract = _remoteContracts[remoteBlockchainID];
            _updateRemotePausedState(remoteBlockchainID, remoteContract, true, feeInfo);
        }
    }

    /**
     * @notice Internal function to unpause all remote contracts
     * @param feeInfo Information about the fee to pay for cross-chain messages
     */
    function _unpauseRemotes(
        TeleporterFeeInfo memory feeInfo
    ) internal {
        for (uint256 i = 0; i < _registeredChains.length; i++) {
            bytes32 remoteBlockchainID = _registeredChains[i];
            address remoteContract = _remoteContracts[remoteBlockchainID];
            _updateRemotePausedState(remoteBlockchainID, remoteContract, false, feeInfo);
        }
    }

    /**
     * @notice Internal function to update the pause state on a remote chain
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @param remoteContract The address of the contract on the destination chain
     * @param pauseState The pause state to set
     * @param feeInfo Information about the fee to pay for the cross-chain message
     */
    function _updateRemotePausedState(
        bytes32 destinationBlockchainID,
        address remoteContract,
        bool pauseState,
        TeleporterFeeInfo memory feeInfo
    ) internal {
        ExtensionMessage[] memory extensions = new ExtensionMessage[](1);
        extensions[0] = ExtensionMessage({
            key: PAUSABLE_EXTENSION_ID,
            value: abi.encode(PausableExtensionMessage({paused: pauseState}))
        });

        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.UPDATE_EXTENSIONS, payload: abi.encode(extensions)});

        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: remoteContract,
                feeInfo: feeInfo,
                requiredGasLimit: UPDATE_PAUSE_STATE_GAS_LIMIT,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );

        emit UpdateRemotePausedState(messageID, destinationBlockchainID, remoteContract, pauseState);
    }
}
