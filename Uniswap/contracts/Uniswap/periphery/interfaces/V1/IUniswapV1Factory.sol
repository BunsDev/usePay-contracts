// SPDX-License-Identifier: SEE LICENSE IN LICENSE.md

pragma solidity >=0.5.0;

interface IUniswapV1Factory {
    function getExchange(address) external view returns (address);
}
