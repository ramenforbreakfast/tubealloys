pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {VariancePosition} from "./VariancePosition.sol";


contract Orderbook is Ownable {
    using SafeMath for uint256;

    //Struct that holds information necessary to check for an open order.
    struct Order {
        uint256 askPrice; //Ask price per unit for the order.
        uint256 vaultId; //Index for the seller's position.
        address sellerAddress; //Address of the seller.
        bool unfilled; //Has order been filled?
    }

    mapping(address => VariancePosition.UserPositions) public userPositions; //Positions held by each seller or buyer.

    Order[] public openOrders; //Array of all orders sorted first by strike and then ask price.

    uint256 public contractEpoch; //epoch for this orderbook

    constructor(uint256 epoch) {
        contractEpoch = epoch;
    }

    function getOrder(uint256 index) external view returns(uint256, uint256, address) {
        Order memory currOrder = openOrders[index];
        return(currOrder.askPrice, currOrder.vaultId, currOrder.sellerAddress);
    }

    function getPosition(address owner, uint256 index) external view returns(uint256, uint256, uint256, uint256) {
        VariancePosition.Position memory currPosition = userPositions[owner].positions[index];
        return(currPosition.strike, currPosition.longPositionAmount, currPosition.shortPositionAmount, userPositions[owner].sellerPayment);
    }

    /*
    * Open a sell order for a specific strike and ask price.
    */
    function sellOrder(address seller, uint256 strike, uint256 askPrice, uint256 collateral) onlyOwner external {
        require(contractEpoch > block.timestamp);
        uint256 index;

        //Find if the seller already has a position at this strike. Otherwise, get the index for a new position to be created.
        index = VariancePosition._findPositionIndex(userPositions[seller], strike);
        //Create or add to an existing position for the seller.
        VariancePosition._addToPosition(userPositions[seller], strike, collateral, collateral, 0, index);
        //Add this new sell order to the orderbook.
        _addToOrderbook(seller, strike, askPrice, index);
    }

    /*
    * Fill a buy order from the open orders that we maintain. We go from minimum strike and fill based on the number of units the buyer wants.
    */
    function fillBuyOrderbyUnitAmount(address buyer, uint256 minStrike, uint256 unitAmount) onlyOwner external {
        require(contractEpoch > block.timestamp);
        uint256 i;
        uint256 currStrike;
        uint256 currId;
        uint256 currLongPositionAmount;
        uint256 adjustedAmount;
        uint256 buyerPositionIndex;
        address currSeller;

        for(i = 0; i < openOrders.length; i++) {
            currId = openOrders[i].vaultId; //Get position index from order.
            currSeller = openOrders[i].sellerAddress; //Get seller from order.
            currStrike = userPositions[currSeller].positions[currId].strike; //Get strike from order.
            currLongPositionAmount = userPositions[currSeller].positions[currId].longPositionAmount; //Get long position amount available from order.
            if(unitAmount == 0) { //If we have filled already desired units from buyer, exit loop.
                break;
            } else if(openOrders[i].unfilled && currStrike >= minStrike) { //Check the order is still open and we are at desired minimum strike.
                if(unitAmount >= currLongPositionAmount) { //Check how much the current order can fill based on what is left from buyer units.
                    adjustedAmount = currLongPositionAmount;
                    openOrders[i].unfilled = false; //Signal order has been filled.
                } else {
                    adjustedAmount = unitAmount;
                }
                VariancePosition._removeFromPosition(userPositions[currSeller], adjustedAmount, 0, 0, currId); //Remove the long position amount that has been filled from seller.
                VariancePosition._addToPosition(userPositions[currSeller], currStrike, 0, 0, adjustedAmount, currId); //Add payout seller gets from buyer for filling this order.
                buyerPositionIndex = VariancePosition._findPositionIndex(userPositions[buyer], currStrike); //Find if buyer has an open position to add long position to.
                VariancePosition._addToPosition(userPositions[buyer], currStrike, adjustedAmount, 0, 0, buyerPositionIndex); //Add the long units to buyer position.
                unitAmount = unitAmount.sub(adjustedAmount); //Update the remaining buyer units after the transaction performed.
            }
        }
    }

    /*
    * Add a new sell order to the orderbook struct.
    */
    function _addToOrderbook(address owner, uint256 strike, uint256 askPrice, uint256 vaultId) internal {
        uint256 i;
        uint256 currStrike;
        uint256 currAskPrice;
        uint256 currId;
        address currAddr;
        uint256 orderSize = openOrders.length;

        if(orderSize == 0) {
            openOrders.push(Order(askPrice, vaultId, owner, true)); //If this is first order, just push it into the struct.
            return;
        }

        for(i = 0; i < orderSize; i++) {
            currAddr = openOrders[i].sellerAddress; //Get seller from order.
            currId = openOrders[i].vaultId; //Get position index from order.
            currAskPrice = openOrders[i].askPrice; //Get ask price from order.
            currStrike = userPositions[currAddr].positions[currId].strike; //Get strike from order.
            if(strike == currStrike && currAddr == owner && currAskPrice == askPrice) { //If the current order matches the new order, we exit out because its same so no need to update.
                break;
            } else if(strike < currStrike || (strike == currStrike && askPrice < currAskPrice)) {
                _addNewOrder(owner, askPrice, vaultId, i); //Add new order into array in the first index where it has either lower strike or same strike but lower ask price.
                break;
            } else if(i == orderSize - 1) {
                openOrders.push(Order(askPrice, vaultId, owner, true)); //If at the last entry in the orders, push this at the end.
            }
        }
    }

    /*
    * Add an order to the specified index and shift every order after the index one spot to the right.
    */
    function _addNewOrder(address addr, uint256 askPrice, uint256 vaultId, uint256 index) internal {
        uint256 i;
        uint256 currId;
        uint256 currAskPrice;
        address currAddr;
        bool currUnfilled;
        uint256 prevId;
        uint256 prevAskPrice;
        address prevAddr;
        bool prevUnfilled;

        openOrders.push(Order(0, 0, address(0), false)); //Push one new empty order to the orderbook struct. This will get filled by the order shifted to the right.
        currId = vaultId; //Order parameters to be added at the starting index.
        currAddr = addr;
        currAskPrice = askPrice;
        currUnfilled = true;
        for(i = index; index < openOrders.length; i++) {
            prevAskPrice = openOrders[i].askPrice; //Keep the old order at this index because it will be added to next one.
            prevId = openOrders[i].vaultId;
            prevAddr = openOrders[i].sellerAddress;
            prevUnfilled = openOrders[i].unfilled;
            openOrders[i].askPrice = currAskPrice; //Update the current order to the one before it or the new order being inserted.
            openOrders[i].vaultId = currId;
            openOrders[i].sellerAddress = currAddr;
            openOrders[i].unfilled = currUnfilled;
            currId = prevId; //Store the old order as current because it will replace the next one.
            currAddr = prevAddr;
            currAskPrice = prevAskPrice;
            currUnfilled = prevUnfilled;
        }
    }
}