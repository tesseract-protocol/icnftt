// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721TokenHome {
    function getRegisteredChains() external view returns (bytes32[] memory);

    function getBlockchainID() external view returns (bytes32);

    event RemoteChainRegistered(bytes32 indexed blockchainID, address indexed remoteAddress);
}
