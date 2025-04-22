// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "./interfaces/IERC721Transferrer.sol";
import {ExtensionMessage} from "./interfaces/IERC721Transferrer.sol";

abstract contract ERC721TokenTransferrer is IERC721Transferrer {
    function _updateExtensions(
        ExtensionMessage[] memory extensions
    ) internal virtual;

    function _getExtensionMessages(
        uint256 tokenId
    ) internal virtual returns (ExtensionMessage[] memory);
}
