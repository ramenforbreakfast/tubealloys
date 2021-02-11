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
     * @param _strikeVar strike variance of user's variance position
     * @param _realizedVar realized variance pulled from the oracle
     * @param longPosition user's long position for the specified strike
     * @param shortPosition user's short position for the specified strike
     */
    function calcPositionSettlement(
        uint256 _realizedVar,
        uint256 _strikeVar,
        int128 longPosition,
        int128 shortPosition
    ) internal returns (uint256) {
        // Convert variance into decimalized representation i.e. 150% variance is 1.5
        // This will obviously depend on how variance oracle is implemented, we can change math operations later
        int128 realizedVar = ABDKMath64x64.divu(_realizedVar, 100);
        int128 strikeVar = ABDKMath64x64.divu(_strikeVar, 100);
        uint256 longPayoutPerSwap = calcPayoutPerSwap(strikeVar, realizedVar);
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
     * @param strikeVar strike variance for the swap in decimal representation
     * @param realizedVar realized variance for the swap in decimal representation
     */
    function calcPayoutPerSwap(int128 strikeVar, int128 realizedVar)
        internal
        returns (uint256)
    {
        uint256 payoutPerSwap =
            strikeVar < realizedVar
                ? ABDKMath64x64.mulu(
                    ABDKMath64x64.sub(realizedVar, strikeVar),
                    1e17
                ) // multiply difference times 0.1 ETH in wei
                : 0;
        // fully collateralized, payout cannot exceed size of swap
        return payoutPerSwap > 1e17 ? 1e17 : payoutPerSwap;
    }
}
