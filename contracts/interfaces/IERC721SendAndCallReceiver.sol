// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IERC721SendAndCallReceiver
 * @dev Interface for contracts that can receive ERC721 tokens via a sendAndCall operation.
 *
 * @notice IMPORTANT IMPLEMENTATION DETAILS:
 * 1. When implementing this interface, if your contract needs to take ownership of the token,
 *    you MUST call transferFrom on the tokenAddress to transfer the token from the calling contract to yourself.
 * 2. If your implementation does not transfer the token, or if the function reverts, the token will be sent
 *    to the fallback recipient address that was specified in the original sendAndCall operation.
 * 3. The calling contract approves your contract to transfer the token before calling receiveToken.
 * 4. Make sure your implementation handles the token transfer appropriately.
 */
interface IERC721SendAndCallReceiver {
    /**
     * @notice Called by an ERC721TokenRemote contract when a token is sent to this contract.
     * @dev If this function wants to take ownership of the token, it MUST call transferFrom to move the token
     * from the calling contract to itself. If this function does not transfer the token, or if it reverts,
     * the calling contract will transfer the token to the fallback recipient address that was specified in the original sendAndCall operation.
     *
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
