pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {SafeDecimalMath} from "./SafeDecimalMath.sol";

library Settlement {
    using SafeMathUpgradeable for uint256;
    // 1e17 wei for 0.1 variance units adjusted to fixed point 8 precision
    uint256 constant VARIANCE_UNIT = 1e25;

    /**
     * @notice settle a swap position, add the settlement payout to their position for the user to redeem.
     * @param realizedVar realized variance fixed point 8 precision
     * @param strikeVar strike variance fixed point 8 precision
     * @param longPosition user's long position fixed point 8 precision
     * @param shortPosition user's short position fixed point 8 precision
     */
    function calcPositionSettlement(
        uint256 realizedVar,
        uint256 strikeVar,
        uint256 longPosition,
        uint256 shortPosition
    ) internal pure returns (uint256) {
        uint256 longPayoutPerSwap = calcPayoutPerSwap(realizedVar, strikeVar);
        uint256 shortPayoutPerSwap = VARIANCE_UNIT.sub(longPayoutPerSwap);
        uint256 longPayout =
            SafeDecimalMath.multiplyDecimal(longPosition, longPayoutPerSwap);
        uint256 shortPayout =
            SafeDecimalMath.multiplyDecimal(shortPosition, shortPayoutPerSwap);
        return shortPayout.add(longPayout);
    }

    /**
     * @notice calculates long payout of swap in wei based on the strike/realized variance.
     * @param realizedVar realized variance fixed point 8 precision
     * @param strikeVar strike variance fixed point 8 precision
     */
    function calcPayoutPerSwap(uint256 realizedVar, uint256 strikeVar)
        internal
        pure
        returns (uint256)
    {
        uint256 payoutPerSwap =
            strikeVar < realizedVar
                ? SafeDecimalMath.multiplyDecimal(
                    (realizedVar.sub(strikeVar)),
                    VARIANCE_UNIT
                )
                : 0;
        // fully collateralized, payout cannot exceed size of swap
        return payoutPerSwap > VARIANCE_UNIT ? VARIANCE_UNIT : payoutPerSwap;
    }
}
