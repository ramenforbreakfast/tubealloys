pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";


/*
* A library for maintaining the variance positions of sellers and buyers.
*/
library VariancePosition {
    using SafeMath for uint256;

    //Individual position struct
    struct Position {
        //The strike realized variance of the position
        uint256 strike;
        //The amount of long position units. This value represents a call on the variance swap at realized strike.
        uint256 longPositionAmount;
        //The amount of short position units. This value represents the inverse of the longPositionAmount.
        uint256 shortPositionAmount;
        //The amount this position has been paid in ether. Updated when filling orders from sellers.
        uint256 sellerPayment;
    }

    /*
    * Pushes a new empty position into the array for an address.
    */
    function _createPosition(Position[] storage position) internal {
        position.push(Position(0, 0, 0, 0));
    }

    /*
    * This function will check if an index is one greater than the size of the position array. If it is, it will create a new position and update with values. Otherwise,
    * it will just add to an already existing position.
    */
    function addToPosition(Position[] storage position, uint256 strike, uint256 sellAmount, uint256 sellerPay, uint256 index) external {
        require(index < position.length + 1);

        if(index == position.length) {
            _createPosition(position);
        }

        position[index].strike = strike;
        position[index].longPositionAmount = position[index].longPositionAmount.add(sellAmount);
        position[index].shortPositionAmount = position[index].shortPositionAmount.add(sellAmount);
        position[index].sellerPayment = position[index].sellerPayment.add(sellerPay);
    }

    /*
    * Remove long and short units as well as sellerPay from a position. This function is used for filling orders. 
    */
    function removeFromPosition(Position[] storage position, uint256 longAmount, uint256 shortAmount, uint256 sellerPay, uint256 index) external {
        require(index < position.length);

        position[index].longPositionAmount = position[index].longPositionAmount.sub(longAmount);
        position[index].shortPositionAmount = position[index].shortPositionAmount.sub(shortAmount);
        position[index].sellerPayment = position[index].sellerPayment.sub(sellerPay);
    }

    /*
    * Find the index of a position given the realizec variance strike and ask price. Otherwise, return position length.
    */
    function findPositionIndex(Position[] storage position, uint256 strike) external view returns(uint256) {
        uint256 i;

        for(i = 0; i < position.length; i++) {
            if(position[i].strike == strike) {
                return (i);
            }
        }
        return (position.length);
    }
}