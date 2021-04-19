pragma solidity ^0.7.3;
import {SafeDecimalMath} from "./SafeDecimalMath.sol";

contract Oracle {
    using SafeDecimalMath for uint256;

    // Fake oracle contract for development purposes
    function getRealized(uint256 roundStart, uint256 roundEnd)
        external
        view
        returns (uint256)
    {
        uint256 realized = SafeDecimalMath.newFixed(150);
        return realized;
    }

    function getLatestImpliedVariance() external view returns (uint256) {
        uint256 implied = SafeDecimalMath.newFixed(120);
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
