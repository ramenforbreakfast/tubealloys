pragma solidity ^0.7.3;

interface OracleInterface {
    function getRealized(uint256 roundStart, uint256 roundEnd)
        external
        view
        returns (uint256);

    function getLatestImpliedVariance() external view returns (uint256);

    function isDisputePeriodOver(uint256 roundEnd) external view returns (bool);
}
