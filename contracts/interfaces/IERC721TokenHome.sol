// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "./IERC721Transferrer.sol";

struct UpdateURIInput {
    bytes32 destinationBlockchainID;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
}

interface IERC721TokenHome is IERC721Transferrer {
    function getRegisteredChains() external view returns (bytes32[] memory);

    function getRegisteredChainsLength() external view returns (uint256);

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
