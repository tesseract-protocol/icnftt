// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721TokenHome {
    function getRegisteredChains() external view returns (bytes32[] memory);

    function getBlockchainID() external view returns (bytes32);

    event BaseURIUpdated(string newBaseURI);

    event RemoteChainRegistered(bytes32 indexed blockchainID, address indexed remote);

    event UpdateRemoteBaseURI(
        bytes32 indexed teleporterMessageID,
        bytes32 indexed destinationBlockchainID,
        address indexed remote,
        string baseURI
    );

    event UpdateRemoteTokenURI(
        bytes32 indexed teleporterMessageID,
        bytes32 indexed destinationBlockchainID,
        address indexed remote,
        uint256 tokenId,
        string uri
    );
}
