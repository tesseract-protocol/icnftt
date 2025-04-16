// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "./IERC721Transferrer.sol";

interface IERC721TokenRemote is IERC721Transferrer {
    function getHomeChainId() external view returns (bytes32);

    function getHomeTokenAddress() external view returns (address);

    function getBlockchainID() external view returns (bytes32);

    function getIsRegistered() external view returns (bool);

    event TokenMinted(uint256 indexed tokenId, address indexed owner);

    event TokenBurned(uint256 indexed tokenId, address indexed owner);

    event RemoteBaseURIUpdated(string indexed baseURI);

    event RemoteTokenURIUpdated(uint256 indexed tokenId, string indexed uri);

    event HomeChainRegistered(bytes32 indexed chainId, address indexed homeAddress);
}
