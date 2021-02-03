pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";

library VariancePosition {
    using SafeMath for uint256;

    struct Position {
        uint256 expiryTimestamp;
        uint256 strike;
        uint256 longPositionAmount;
        uint256 shortPositionAmount;
        uint256 sellerPayment;
    }

    function _createPosition(Position[] storage position) internal {
        position.push(Position(0, 0, 0, 0, 0));
    }

    function _deletePosition(Position[] storage position, uint256 index) internal {
        require(index < position.length);
        uint256 i;

        position[index] = position[position.length - 1];
        delete position[position.length - 1];
        position.pop();
    }

    function addToPosition(Position[] storage position, uint256 expiryTime, uint256 strike, uint256 longAmount, uint256 shortAmount, uint256 sellerPay, uint256 index) external {
        require(index < position.length + 1);

        if(index == position.length) {
            _createPosition(position);
        }

        position[index].expiryTimestamp = expiryTime;
        position[index].strike = strike;
        position[index].longPositionAmount = position[index].longPositionAmount.add(longAmount);
        position[index].shortPositionAmount = position[index].shortPositionAmount.add(shortAmount);
        position[index].sellerPayment = position[index].sellerPayment.add(sellerPay);
    }

    function removeFromPosition(Position[] storage position, uint256 longAmount, uint256 shortAmount, uint256 sellerPay, uint256 index) external {
        require(index < position.length);

        position[index].longPositionAmount = position[index].longPositionAmount.sub(longAmount);
        position[index].shortPositionAmount = position[index].shortPositionAmount.sub(shortAmount);
        position[index].sellerPayment = position[index].sellerPayment.sub(sellerPay);

        if(position[index].longPositionAmount == 0 && position[index].shortPositionAmount == 0 && position[index].sellerPayment == 0) {
            _deletePosition(position, index);
        }
    }

    function findPositionIndex(Position[] storage position, uint256 expiryTime, uint256 strike) external view returns(uint256) {
        uint256 i;
        for(i = 0; i < position.length; i++) {
            if(position[i].expiryTimestamp == expiryTime && position[i].strike == strike) {
                return (i);
            }
        }
        return (position.length);
    }
}