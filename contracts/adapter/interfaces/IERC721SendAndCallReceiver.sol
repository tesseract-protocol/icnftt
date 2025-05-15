// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IERC721SendAndCallReceiver
 * @dev Interface for contracts that can receive multiple ERC721 tokens via a sendAndCall operation.
 *
 * @notice IMPORTANT IMPLEMENTATION DETAILS:
 * 1. When implementing this interface, if your contract needs to take ownership of the tokens,
 *    you MUST call transferFrom on the tokenAddress to transfer each token from the calling contract to yourself.
 * 2. If your implementation does not transfer some or all tokens, or if the function reverts, any tokens that remain
 *    in the calling contract's possession will be sent to the fallback recipient address.
 * 3. The calling contract approves your contract to transfer all tokens before calling receiveTokens.
 * 4. Make sure your implementation handles the token transfers appropriately.
 * 5. IMPORTANT: The system does NOT verify if the fallback recipient is capable of handling ERC721 tokens.
 *    You must ensure that the fallback recipient address specified during the sendAndCall operation
 *    is able to properly receive and handle ERC721 tokens.
 */
interface IERC721SendAndCallReceiver {
    /**
     * @notice Called by an ERC721TokenRemote contract when tokens are sent to this contract.
     * @dev If this function wants to take ownership of the tokens, it MUST call transferFrom to move each token
     * from the calling contract to itself. If this function does not transfer some or all tokens, or if it reverts,
     * any tokens that remain in the calling contract's possession will be sent to the fallback recipient address.
     * The system does not verify if the fallback recipient can handle ERC721 tokens, so ensure it is capable of
     * receiving them properly.
     *
     * @param sourceBlockchainID The blockchain ID the tokens were sent from
     * @param originTokenTransferrerAddress The address of the token transferrer contract on the source blockchain
     * @param originSenderAddress The address of the sender on the source blockchain
     * @param tokenAddress The address of the ERC721 token contract on this blockchain
     * @param tokenIds The IDs of the tokens being sent
     * @param payload Additional data to be handled by the recipient contract
     */
    function receiveTokens(
        bytes32 sourceBlockchainID,
        address originTokenTransferrerAddress,
        address originSenderAddress,
        address tokenAddress,
        uint256[] calldata tokenIds,
        bytes calldata payload
    ) external;
}
