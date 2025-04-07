// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ICNFTTHome} from "../src/ICNFTTHome.sol";
import {ICNFTTRemote} from "../src/ICNFTTRemote.sol";

contract ICNFTTTest is Test {
    ICNFTTHome public homeToken;
    ICNFTTRemote public remoteToken;
    
    address public deployer = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256 public tokenId = 1;
    string public tokenURI = "ipfs://QmTokenURI";
    uint32 public homeChainId = 1;
    uint32 public remoteChainId = 2;
    
    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy Home and Remote tokens
        homeToken = new ICNFTTHome("Home Token", "HOME");
        remoteToken = new ICNFTTRemote("Remote Token", "REMOTE", homeChainId, address(homeToken));
        
        // Register remote token on home token
        homeToken.registerRemoteContract(remoteChainId, address(remoteToken));
        
        // Mint a token to user1
        homeToken.mint(user1, tokenId, tokenURI);
        
        vm.stopPrank();
    }
    
    function test_HomeTokenMint() public {
        assertEq(homeToken.ownerOf(tokenId), user1);
        assertEq(homeToken.tokenURI(tokenId), tokenURI);
    }
    
    function test_HomeToRemoteFlow() public {
        // User1 approves and sends token to remote chain
        vm.startPrank(user1);
        homeToken.sendToken(tokenId, remoteChainId, user2);
        vm.stopPrank();
        
        // Check that token is locked on home chain
        assertTrue(homeToken.isTokenLocked(tokenId));
        
        // Simulate the cross-chain message by calling receive on remote token
        vm.prank(deployer);
        remoteToken.receiveToken(tokenId, user2);
        
        // Check ownership on remote chain
        assertEq(remoteToken.ownerOf(tokenId), user2);
        
        // Set token URI on remote (in a complete implementation, this would happen automatically)
        vm.prank(deployer);
        remoteToken.setTokenURI(tokenId, tokenURI);
        
        // Check token URI on remote chain
        assertEq(remoteToken.tokenURI(tokenId), tokenURI);
    }
    
    function test_RemoteToHomeFlow() public {
        // First send token to remote chain
        vm.prank(user1);
        homeToken.sendToken(tokenId, remoteChainId, user2);
        
        vm.prank(deployer);
        remoteToken.receiveToken(tokenId, user2);
        
        // Now send it back
        vm.prank(user2);
        remoteToken.returnToken(tokenId, user1);
        
        // Simulate the cross-chain message by calling receive on home token
        vm.prank(deployer);
        homeToken.receiveToken(tokenId, user1);
        
        // Check ownership is back to user1 on home chain
        assertEq(homeToken.ownerOf(tokenId), user1);
        assertFalse(homeToken.isTokenLocked(tokenId));
        
        // Token should not exist on remote chain
        vm.expectRevert(); // ERC721: owner query for nonexistent token
        remoteToken.ownerOf(tokenId);
    }
} 