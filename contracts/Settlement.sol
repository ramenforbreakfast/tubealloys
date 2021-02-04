pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";

library Settlement {
    /** WORK IN PROGRESS 
        MANY FUNCTIONS ARE BASICALLY PSEUDO CODE SINCE OTHER COMPONENTS DO NOT EXIST YET
     */
    uint256 internal constant BASE = 1e8; // 1e8 gwei = 0.1 ETH

    //
    /**
     * @notice checks with oracle if realized variance value at round end date is valid
     * @param _roundEnd date that the round ends on
     */
    function isSettlementAllowed(uint256 _roundEnd) public view returns (bool) {
        // boilerplate call to an oracle to determine if realized variance obtained is valid
        bool isRealizedFinalized = oracle.isDisputePeriodOver(_roundEnd);
        return isRealizedFinalized;
    }

    /**
     * @notice settle a swap position, return the payout in gwei for the total position amount
     * @param receiver address of user calling settlement contract
     * @param _positionID index of position in user -> position mapping
     */
    function settleSwapPosition(address _receiver, uint256 _positionIDX)
        external
    {
        SwapInterface swap = SwapInterface(_positionIDX);
        (
            uint256 strikeVar,
            uint256 longPosition,
            uint256 shortPosition,
            uint256 roundEnd
        ) = swap.getSwapDetails();
        require(
            now > roundEnd,
            "Settlement: Cannot settle swap, round has not ended!"
        );
        require(isSettlementAllowed(roundEnd));

        uint256 longPayout =
            (getPayoutPerSwap(strikeVar, roundEnd)).mul(longPosition);
        uint256 shortPayout = (1e8.sub(longPayout)).mul(shortPosition);
        uint256 totalPayout = shortPayout.add(longPayout);

        swap.removeShort(msg.sender, shortPosition);
        swap.removeLong(msg.sender, longPosition);
        pool.transferToUser(_receiver, totalPayout);
        // delete position
        emit Settlement(_receiver, _positionIDX, msg.sender, totalPayout);
    }

    /**
     * This function should be declared elsewhere and accessible not from Settlement contract probably?
     * @notice pulls realized variance from oracle, checks if realized value is valid
     * @param _date date to retrieve realized variance for
     */
    function _getRealizedVariance(uint256 _date)
        internal
        view
        returns (uint256 memory)
    {
        (uint256 realizedVar, bool varFinalized) = oracle.getRealized(_date);
        require(
            varFinalized,
            "Settlement: Realized variance from oracle not settled yet"
        );
        return varFinalized;
    }

    /**
     * @notice calculates long payout of swap based on the strike/realized variance.
     * @param _strikeVar strike variance for the swap
     * @param _roundEnd date that the round ends on
     */
    function _getPayoutPerSwap(uint256 _strikeVar, uint256 _roundEnd)
        internal
        returns (uint256 memory)
    {
        uint256 strikeVar = _strikeVar.mul(BASE);
        uint256 realizedVar = _getRealizedVariance(_roundEnd).mul(BASE);
        uint256 varDifference =
            strikeVar < realizedVar
                ? realizedVar.sub(strikeVar) // 1.515e8 -1.5e8 = 1.5e6
                : ZERO;
        // fully collateralized, payout cannot exceed size of swap
        return varDifference > 1e8 ? 1e8 : varDifference; // 1.5e6 gwei
    }
}
