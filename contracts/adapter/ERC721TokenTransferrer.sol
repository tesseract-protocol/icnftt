// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721Transferrer} from "./interfaces/IERC721Transferrer.sol";
import {IWarpMessenger} from "@subnet-evm-contracts/IWarpMessenger.sol";

/**
 * @title ERC721TokenTransferrer
 * @dev An abstract base contract for cross-chain ERC721 token transferring functionality.
 *
 * This contract serves as the foundation for both Home and Remote token contracts in the
 * Interchain NFT (ICNFTT) system.
 *
 * The contract is designed to be extended by both Home and Remote token implementations.
 */
abstract contract ERC721TokenTransferrer is IERC721Transferrer {
    /// @notice The blockchain ID of the current chain
    /// forge-lint: disable-next-item(screaming-snake-case-immutable)
    bytes32 internal immutable _blockchainId;

    /**
     * @notice Initializes the ERC721TokenTransferrer contract
     */
    constructor() {
        _blockchainId = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    /**
     * @notice Returns the blockchain ID of the current chain
     * @return The blockchain ID
     */
    /// forge-lint: disable-next-item(mixed-case-function)
    function getBlockchainID() external view override returns (bytes32) {
        return _blockchainId;
    }
}
