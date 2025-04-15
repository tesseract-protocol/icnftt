// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IERC721SendAndCallReceiver
 * @dev Interface for contracts that can receive ERC721 tokens via a sendAndCall operation.
 * This is similar to the ERC20 sendAndCall mechanism but for NFTs.
 */
interface IERC721SendAndCallReceiver {
    /**
     * @notice Called by an ERC721TokenRemote contract when a token is sent to this contract.
     * @param sourceBlockchainID The blockchain ID the tokens were sent from
     * @param originTokenTransferrerAddress The address of the token transferrer contract on the source blockchain
     * @param originSenderAddress The address of the sender on the source blockchain
     * @param tokenAddress The address of the ERC721 token contract on this blockchain
     * @param tokenId The ID of the token being sent
     * @param payload Additional data to be handled by the recipient contract
     */
    function receiveToken(
        bytes32 sourceBlockchainID,
        address originTokenTransferrerAddress,
        address originSenderAddress,
        address tokenAddress,
        uint256 tokenId,
        bytes calldata payload
    ) external;
}
