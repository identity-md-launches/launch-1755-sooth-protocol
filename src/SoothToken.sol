// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Sooth Protocol
/// @notice A fixed supply ERC-20 with 18 decimals and no administrative powers.
contract SoothToken is ERC20 {
    /// @notice One billion SOOTH, expressed in the smallest token unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev In the launch flow, msg.sender is the factory that distributes the supply.
    constructor() ERC20("Sooth Protocol", "SOOTH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
