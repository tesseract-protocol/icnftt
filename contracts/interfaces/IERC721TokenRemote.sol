// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721TokenRemote {
    function getHomeChainId() external view returns (bytes32);
    function getHomeTokenAddress() external view returns (address);

    event TokenMinted(uint256 indexed tokenId, address indexed owner);
    event TokenBurned(uint256 indexed tokenId, address indexed owner);
    event RemoteBaseURIUpdated(string indexed baseURI);
    event RemoteTokenURIUpdated(uint256 indexed tokenId, string indexed uri);
    event HomeChainRegistered(bytes32 indexed chainId, address indexed homeAddress);
}
