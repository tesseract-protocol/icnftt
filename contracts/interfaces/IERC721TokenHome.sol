// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721TokenHome {
    // View function to check if token is locked
    function isTokenLocked(
        uint256 tokenId
    ) external view returns (bool);

    // Returns all chains where this token has Remote versions
    function getRegisteredChains() external view returns (bytes32[] memory);

    event TokenLocked(
        uint256 indexed tokenId, bytes32 indexed destinationBlockchainID, address indexed recipient
    );
    event TokenUnlocked(
        uint256 indexed tokenId, bytes32 indexed sourceBlockchainID, address indexed recipient
    );
    event RemoteChainRegistered(bytes32 indexed blockchainID, address indexed remoteAddress);
}
