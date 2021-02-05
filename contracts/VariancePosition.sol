pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";


/*
* A library for maintaining the variance positions of sellers and buyers.
*/
library VariancePosition {
    using SafeMath for uint256;

    //Individual position struct
    struct Position {
        //The strike realized variance of the position.
        uint256 strike;
        //The amount of long position units. This value represents a call on the variance swap at realized strike.
        uint256 longPositionAmount;
        //The amount of short position units. This value represents the inverse of the longPositionAmount.
        uint256 shortPositionAmount;
    }

    //Structure that holds all positions of an address, as well as the total payment they have received
    struct UserPositions {
        //Array of all positions a user holds.
        Position[] positions;
        //The total amount a user has been paid in discrete units.
        uint256 sellerPayment;
    }

    /*
    * Pushes a new empty position into the array for an address.
    */
    function _createPosition(UserPositions storage userPositions, uint256 strike) internal {
        userPositions.positions.push(Position(strike, 0, 0));
    }

    /*
    * This function will check if an index is one greater than the size of the position array. If it is, it will create a new position and update with values. Otherwise,
    * it will just add to an already existing position.
    */
    function _addToPosition(UserPositions storage userPositions, uint256 strike, uint256 longAmount, uint256 shortAmount, uint256 sellerPay, uint256 index) internal {
        require(index < userPositions.positions.length + 1);

        if(index == userPositions.positions.length) {
            _createPosition(userPositions, strike);
        }

        userPositions.positions[index].longPositionAmount = userPositions.positions[index].longPositionAmount.add(longAmount);
        userPositions.positions[index].shortPositionAmount = userPositions.positions[index].shortPositionAmount.add(shortAmount);
        userPositions.sellerPayment = userPositions.sellerPayment.add(sellerPay);
    }

    /*
    * Remove long and short units as well as sellerPay from a position. This function is used for filling orders. 
    */
    function _removeFromPosition(UserPositions storage userPositions, uint256 longAmount, uint256 shortAmount, uint256 sellerPay, uint256 index) internal {
        require(index < userPositions.positions.length);

        userPositions.positions[index].longPositionAmount = userPositions.positions[index].longPositionAmount.sub(longAmount);
        userPositions.positions[index].shortPositionAmount = userPositions.positions[index].shortPositionAmount.sub(shortAmount);
        userPositions.sellerPayment = userPositions.sellerPayment.sub(sellerPay);
    }

    /*
    * Set seller payment for user to 0 and return the payment. This represents a seller getting their payout for the open orders that were filled.
    */
    function _settleOrderPayment(UserPositions storage userPositions) internal returns(uint256) {
        uint256 sellerPayment = userPositions.sellerPayment;
        userPositions.sellerPayment = 0;
        return sellerPayment;
    }

    /*
    * Find the index of a position given the realizec variance strike and ask price. Otherwise, return position length.
    */
    function _findPositionIndex(UserPositions storage userPositions, uint256 strike) internal view returns(uint256) {
        uint256 i;

        for(i = 0; i < userPositions.positions.length; i++) {
            if(userPositions.positions[i].strike == strike) {
                return (i);
            }
        }
        return (userPositions.positions.length);
    }
}