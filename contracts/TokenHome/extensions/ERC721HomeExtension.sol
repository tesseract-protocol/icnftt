// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ExtensionMessage, ExtensionMessageParams} from "../../interfaces/IERC721Transferrer.sol";
import {ERC721TokenHome} from "../ERC721TokenHome.sol";

abstract contract ERC721HomeExtension is ERC721TokenHome {
    function _getMessage(
        ExtensionMessageParams memory params
    ) internal view virtual returns (ExtensionMessage memory) {}
}
