// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @notice A token whose transfer/transferFrom behavior can be toggled to fail on demand,
 * used to test the require(success, ...) failure branches that a well-behaved token never triggers
 */
contract FailingToken {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    bool public shouldFail;

    /**
     * @notice Toggles whether transfer/transferFrom should fail
     */
    function setShouldFail(bool shouldFail_) external {
        shouldFail = shouldFail_;
    }

    function transfer(address, uint256) external view returns (bool) {
        return !shouldFail;
    }

    function transferFrom(address, address, uint256) external view returns (bool) {
        return !shouldFail;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
