// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ExtensionMessage} from "../../interfaces/IERC721Transferrer.sol";
import {ERC721TokenRemote} from "../ERC721TokenRemote.sol";

abstract contract ERC721RemoteExtension is ERC721TokenRemote {
    function _update(
        ExtensionMessage memory extension
    ) internal virtual {}
}
