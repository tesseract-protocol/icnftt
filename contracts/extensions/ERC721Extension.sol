// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ExtensionMessage, ExtensionMessageParams} from "../interfaces/IERC721Transferrer.sol";

abstract contract ERC721Extension {
    function _update(
        ExtensionMessage memory extension
    ) internal virtual {}

    function _getMessage(
        ExtensionMessageParams memory params
    ) internal view virtual returns (ExtensionMessage memory) {}
}
