pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";

library Settlement {
    /** WORK IN PROGRESS 
        MANY FUNCTIONS/INTERFACES ARE BASICALLY PSEUDO CODE SINCE OTHER COMPONENTS DO NOT EXIST YET
     */
    using SafeMath for uint256;
    uint256 constant varianceUnit = 1e17;

    /**
     * @notice settle a swap position, add the settlement payout to their position for the user to redeem.
     * @param realizedVar realized variance pulled from the oracle
     * @param strikeVar strike variance of user's variance position
     * @param longPosition user's long position for the specified strike
     * @param shortPosition user's short position for the specified strike
     */
    function calcPositionSettlement(
        uint256 realizedVar,
        uint256 strikeVar,
        int128 longPosition,
        int128 shortPosition
    ) internal pure returns (uint256) {
        // Convert variance into decimalized representation i.e. 150% variance is 1.5
        // This will obviously depend on how variance oracle is implemented, we can change math operations later
        uint256 longPayoutPerSwap = calcPayoutPerSwap(realizedVar, strikeVar);
        uint256 shortPayoutPerSwap = varianceUnit.sub(longPayoutPerSwap);
        // multiply signed 64.64 bit fixed point ABDK long position by uint256 payout per swap in wei
        uint256 longPayout =
            ABDKMath64x64.mulu(longPosition, longPayoutPerSwap);
        uint256 shortPayout =
            ABDKMath64x64.mulu(shortPosition, shortPayoutPerSwap);
        return shortPayout.add(longPayout);
    }

    /**
     * @notice calculates long payout of swap in wei based on the strike/realized variance.
     * @param realizedVar realized variance for the swap in decimal representation
     * @param strikeVar strike variance for the swap in decimal representation
     */
    function calcPayoutPerSwap(uint256 realizedVar, uint256 strikeVar)
        internal
        pure
        returns (uint256)
    {
        uint256 payoutPerSwap =
            strikeVar < realizedVar
                ? ((realizedVar.sub(strikeVar)).mul(varianceUnit)).div(100) // multiply difference times 0.1 ETH in wei
                : 0;
        // fully collateralized, payout cannot exceed size of swap
        return payoutPerSwap > varianceUnit ? varianceUnit : payoutPerSwap;
    }
}
