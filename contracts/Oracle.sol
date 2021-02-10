pragma solidity ^0.7.3;

contract Oracle {
    function getRealized(uint256 roundStart, uint256 roundEnd)
        external
        view
        returns (uint256)
    {
        uint256 realized = 150;
        return realized;
    }

    function getLatestImpliedVariance() external view returns (uint256) {
        uint256 implied = 120;
        return implied;
    }

    function isDisputePeriodOver(uint256 roundEnd)
        external
        view
        returns (bool)
    {
        bool testDispute = true;
        return testDispute;
    }
}
