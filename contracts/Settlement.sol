pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";
import {VariancePosition} from "./VariancePosition.sol";

library Settlement {
    /** WORK IN PROGRESS 
        MANY FUNCTIONS/INTERFACES ARE BASICALLY PSEUDO CODE SINCE OTHER COMPONENTS DO NOT EXIST YET
     */
    using SafeMath for uint256;

    /**
     * @notice settle a swap position, add the settlement payout to their position for the user to redeem.
     * @param _realizedVar realized variance pulled from the oracle
     * @param userPositions list of positions that belong to the user
     * @param index index of the position to be settled
     */
    function settleSwapPosition(
        uint256 _realizedVar,
        UserPositions storage userPositions,
        uint256 index
    ) internal {
        // Speak to Andres about changing what view functions exist where because kind of confusing in its current state
        // For example, in controller, I am iterating through the OrderBook to grab a userPositions array.
        // There should be viewPosition function in the VariancePosition library in addition to the getPosition function in OrderBook
        // If I already have the userPosition list and the index, I should not need to poll the orderbook just to view the position
        // Kind of strange that I would have to import the Orderbook contract just to access a view function on the Variance Position itself
        // Orderbook getPosition should then call a view function FROM VariancePosition.
        // Going to implement as if view function was accessible from VariancePosition
        (uint256 _strikeVar, uint128 longPosition, uint128 shortPosition, ) =
            _viewPosition(userPositions, index);
        // Convert variance into decimalized representation i.e. 150% variance is 1.5
        // This will obviously depend on how variance oracle is implemented, we can change math operations later
        uint128 strikeVar = ABDKMath64x64.divu(_strikeVar, 100);
        uint128 realizedVar = ABDKMath64x64.divu(_realizedVar, 100);

        uint256 longPayoutPerSwap = calcPayoutPerSwap(strikeVar, realizedVar);
        uint256 shortPayoutPerSwap = 1e17.sub(longPayoutPerSwap);
        // multiply signed 64.64 bit fixed point ABDK long position by uint256 payout per swap in wei
        uint256 longPayout =
            ABDKMath64x64.mulu(longPosition, longPayoutPerSwap);
        uint256 shortPayout =
            ABDKMath64x64.mulu(shortPosition, shortPayoutPerSwap);
        uint256 totalPayout = shortPayout.add(longPayout);

        _removeFromPosition(
            userPositions,
            longPosition,
            shortPosition,
            0,
            index
        );
        // Another question needs to be brought up, where do we put how much the user can redeem for a swap?
        // It makes more sense to keep this in the VariancePosition, and move sellerPayment somewhere else, to the Orderbook.
        // We would add the User's payout to their Variance Position, and allow them to redeem on expiry date.
        _addPayoutToPosition(userPositions, index, totalPayout);
    }

    /**
     * @notice calculates long payout of swap in wei based on the strike/realized variance.
     * @param strikeVar strike variance for the swap in decimal representation
     * @param realizedVar realized variance for the swap in decimal representation
     */
    function calcPayoutPerSwap(uint128 strikeVar, uint128 realizedVar)
        internal
        returns (uint256 memory)
    {
        uint256 payoutPerSwap =
            strikeVar < realizedVar
                ? ABDKMath64x64.mulu(
                    ABDKMath64x64.sub(realizedVar, strikeVar),
                    1e17
                ) // multiply difference times 0.1 ETH in wei
                : ZERO;
        // fully collateralized, payout cannot exceed size of swap
        return payoutPerSwap > 1e17 ? 1e17 : payoutPerSwap;
    }
}
