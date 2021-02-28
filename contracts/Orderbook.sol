pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {VariancePosition} from "./VariancePosition.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";

contract Orderbook is Ownable {
    using SafeMath for uint256;

    //Struct that holds information necessary to check for an open order.
    struct Order {
        uint256 askPrice; //Ask price in wei per unit for the order.
        uint256 posIdx; //Index for the seller's position.
        address seller; //Address of the seller.
        bool unfilled; //Has order been filled?
    }

    mapping(address => VariancePosition.UserPositions) public userPositions; //Positions held by each seller or buyer.

    Order[] public openOrders; //Array of all orders sorted first by strike and then ask price.

    uint256 public roundStart; //round start timestamp for this orderbook

    uint256 public roundEnd; //round end timestamp for this orderbook

    uint256 public roundImpliedVariance; //Implied Variance used for this orderbook

    address public bookOracle; //Oracle used for querying variance

    address[] public userAddresses; //Addresses that hold positions

    bool public settled; //Has orderbook been settled?

    uint64 constant PAGESIZE = 1000;

    constructor(
        uint256 startTimestamp,
        uint256 endTimestamp,
        address oracle,
        uint256 impliedVariance
    ) {
        roundStart = startTimestamp;
        roundEnd = endTimestamp;
        bookOracle = oracle;
        roundImpliedVariance = impliedVariance;
        settled = false;
    }

    /*
     * Return size of pages used for returning payout information in getBuyOrderbyUnitAmount.
     */
    function getPageSize() external pure returns (uint64) {
        return PAGESIZE;
    }

    /*
     * Return intialized values of orderbook
     */

    function getOrderbookInfo()
        external
        view
        returns (
            uint256,
            uint256,
            address,
            uint256
        )
    {
        return (roundStart, roundEnd, bookOracle, roundImpliedVariance);
    }

    /*
     * Get the length of the orders maintained.
     */
    function getNumberOfOrders() external view returns (uint256) {
        return openOrders.length;
    }

    /*
     * Get the ask price, position id and seller address from an order.
     */
    function getOrder(uint256 index)
        external
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        require(index < openOrders.length);
        Order memory currOrder = openOrders[index];
        return (currOrder.askPrice, currOrder.posIdx, currOrder.seller);
    }

    /*
     * Get the number of positions a specific address holds.
     */
    function getNumberOfUserPositions(address addr)
        external
        view
        returns (uint256)
    {
        return userPositions[addr].positions.length;
    }

    /*
     * Get the position given an address and position index.
     */
    function getPosition(address owner, uint256 index)
        external
        view
        returns (
            uint256,
            int128,
            int128
        )
    {
        require(index < userPositions[owner].positions.length);
        VariancePosition.Position memory currPosition =
            userPositions[owner].positions[index];
        return (
            currPosition.strike,
            currPosition.longPositionAmount,
            currPosition.shortPositionAmount
        );
    }

    /*
     * Display the payout from filled orders for a seller.
     */
    function getFilledOrderPayment(address owner)
        external
        view
        returns (uint256)
    {
        return userPositions[owner].filledOrderPayment;
    }

    /*
     * Display the payout from variance swap settlement.
     */
    function getUserSettlement(address owner) external view returns (uint256) {
        return userPositions[owner].userSettlement;
    }

    /*
     * Get total number of address that hold positions.
     */
    function getNumberOfActiveAddresses() external view returns (uint256) {
        return userAddresses.length;
    }

    /*
     * Get address by index.
     */
    function getAddrByIdx(uint256 index) external view returns (address) {
        require(index < userAddresses.length);
        return userAddresses[index];
    }

    function isSettled() external view returns (bool) {
        return settled;
    }

    /*
     * Set orderbook internal variable to settled to signify the positions of all users have been calculated.
     */
    function settleOrderbook() external onlyOwner {
        settled = true;
    }

    /*
     * Get the payout from filled orders for a seller. Set this value internally to 0 to signify the seller has received this payment.
     */
    function redeemFilledOrderPayment(address owner)
        external
        onlyOwner
        returns (uint256)
    {
        require(!settled);
        return VariancePosition._settleOrderPayment(userPositions[owner]);
    }

    /*
     * Get the total payout for variance swaps. Set this value internally to 0 to signify the seller has received this payment.
     */
    function redeemUserSettlement(address owner)
        external
        onlyOwner
        returns (uint256)
    {
        require(!settled);
        return VariancePosition._redeemUserSettlement(userPositions[owner]);
    }

    /*
     * Set the total payout for variance swaps. This is done from Controller smart contract.
     */
    function setUserSettlement(address owner, uint256 settlement)
        external
        onlyOwner
    {
        require(!settled);
        VariancePosition._setUserSettlement(userPositions[owner], settlement);
    }

    function setBookRoundEnd(uint256 date) external {
        roundEnd = date;
    }

    /*
     * Open a sell order for a specific strike and ask price.
     */
    function sellOrder(
        address seller,
        uint256 strike,
        uint256 askPrice,
        int128 positionSize
    ) external onlyOwner {
        require(roundEnd > block.timestamp);
        require(!settled);
        require(askPrice != 0);
        require(positionSize != 0);
        require(strike != 0);
        uint256 index;

        //Find if the seller already has a position at this strike. Otherwise, get the index for a new position to be created.
        index = VariancePosition._findPositionIndex(
            userPositions[seller],
            strike
        );
        //Create or add to an existing position for the seller.
        VariancePosition._addToPosition(
            userPositions[seller],
            strike,
            positionSize,
            positionSize,
            0,
            index
        );
        //Add this new sell order to the orderbook.
        _addToOrderbook(seller, strike, askPrice, index);
        //Maintain addresses that hold positions
        userAddresses.push(seller);
    }

    /*
     * Fill a buy order from the open orders that we maintain. We go from minimum strike and fill based on the max price in ether the user wants to pay.
     */
    function fillBuyOrderByMaxPrice(
        address buyer,
        uint256 minStrike,
        uint256 maxPrice
    ) external onlyOwner returns (uint256) {
        require(roundEnd > block.timestamp);
        require(!settled);
        uint256 i;
        uint256 currStrike;
        int128 currLongPositionAmount;
        uint256 currAskPrice;
        int128 adjustedAmount;
        int128 unitsFilled;
        uint256 buyerPositionIndex;
        uint256 remainingPosition = maxPrice;

        for (i = 0; i < openOrders.length; i++) {
            currAskPrice = openOrders[i].askPrice; //Get ask price from order.
            currStrike = userPositions[openOrders[i].seller].positions[
                openOrders[i].posIdx
            ]
                .strike; //Get strike from order.
            currLongPositionAmount = userPositions[openOrders[i].seller]
                .positions[openOrders[i].posIdx]
                .longPositionAmount; //Get long position amount available from order.
            if (remainingPosition == 0) {
                //If we have filled already desired units from buyer, exit loop.
                break;
            } else if (openOrders[i].unfilled && currStrike >= minStrike) {
                //Check the order is still open and we are at desired minimum strike.
                unitsFilled = ABDKMath64x64.divu(
                    remainingPosition,
                    currAskPrice
                );
                if (unitsFilled >= currLongPositionAmount) {
                    adjustedAmount = currLongPositionAmount;
                    openOrders[i].unfilled = false; //Signal order has been filled.
                } else {
                    adjustedAmount = unitsFilled;
                }
                VariancePosition._removeFromPosition(
                    userPositions[openOrders[i].seller],
                    adjustedAmount,
                    0,
                    0,
                    openOrders[i].posIdx
                ); //Remove the long position amount that has been filled from seller.
                VariancePosition._addToPosition(
                    userPositions[openOrders[i].seller],
                    currStrike,
                    0,
                    0,
                    ABDKMath64x64.mulu(adjustedAmount, currAskPrice),
                    openOrders[i].posIdx
                ); //Add payout seller gets from buyer for filling this order.
                buyerPositionIndex = VariancePosition._findPositionIndex(
                    userPositions[buyer],
                    currStrike
                ); //Find if buyer has an open position to add long position to.
                VariancePosition._addToPosition(
                    userPositions[buyer],
                    currStrike,
                    adjustedAmount,
                    0,
                    0,
                    buyerPositionIndex
                ); //Add the long units to buyer position.
                remainingPosition = remainingPosition.sub(
                    ABDKMath64x64.mulu(adjustedAmount, currAskPrice)
                );
            }
        }

        if (maxPrice != remainingPosition) {
            //Maintain addresses that hold positions
            userAddresses.push(buyer);
        }

        return remainingPosition;
    }

    /*
     * Get price in wei for buy order from the open orders that we maintain. We go from minimum strike and fill based on the number of units the buyer wants.
     */
    function getBuyOrderByUnitAmount(uint256 minStrike, int128 unitAmount)
        external
        view
        onlyOwner
        returns (
            uint256,
            int128,
            int128[PAGESIZE] memory,
            uint256[PAGESIZE] memory
        )
    {
        require(roundEnd > block.timestamp);
        require(!settled);
        uint256 i;
        uint256 currStrike;
        int128 currLongPositionAmount;
        int128 adjustedAmount;
        uint256 totalPrice = 0;
        int128[PAGESIZE] memory unitsToBuy;
        uint256[PAGESIZE] memory strikesToBuy;
        uint256 ct = 0;

        for (i = 0; i < openOrders.length && ct < PAGESIZE; i++) {
            currStrike = userPositions[openOrders[i].seller].positions[
                openOrders[i].posIdx
            ]
                .strike; //Get strike from order.
            currLongPositionAmount = userPositions[openOrders[i].seller]
                .positions[openOrders[i].posIdx]
                .longPositionAmount; //Get long position amount available from order.
            if (unitAmount == 0) {
                //If we have filled already desired units from buyer, exit loop.
                break;
            } else if (openOrders[i].unfilled && currStrike >= minStrike) {
                //Check the order is still open and we are at desired minimum strike.
                if (unitAmount >= currLongPositionAmount) {
                    //Check how much the current order can fill based on what is left from buyer units.
                    adjustedAmount = currLongPositionAmount;
                } else {
                    adjustedAmount = unitAmount;
                }
                totalPrice = totalPrice.add(
                    ABDKMath64x64.mulu(adjustedAmount, openOrders[i].askPrice)
                );
                unitAmount = ABDKMath64x64.sub(unitAmount, adjustedAmount); //Update the remaining buyer units after the transaction performed.
                unitsToBuy[ct] = adjustedAmount; //Maintain the long units and strikes that can be filled
                strikesToBuy[ct++] = currStrike;
            }
        }

        return (totalPrice, unitAmount, unitsToBuy, strikesToBuy);
    }

    /*
     * Add a new sell order to the orderbook struct.
     */
    function _addToOrderbook(
        address owner,
        uint256 strike,
        uint256 askPrice,
        uint256 posIdx
    ) internal {
        uint256 i;
        uint256 currStrike;
        uint256 currAskPrice;
        uint256 currId;
        address currAddr;
        bool currUnfilled;
        uint256 orderSize = openOrders.length;

        if (orderSize == 0) {
            openOrders.push(Order(askPrice, posIdx, owner, true)); //If this is first order, just push it into the struct.
            return;
        }

        for (i = 0; i < orderSize; i++) {
            currAddr = openOrders[i].seller; //Get seller from order.
            currId = openOrders[i].posIdx; //Get position index from order.
            currAskPrice = openOrders[i].askPrice; //Get ask price from order.
            currUnfilled = openOrders[i].unfilled; //Get filled status from order
            currStrike = userPositions[currAddr].positions[currId].strike; //Get strike from order.
            if (
                strike == currStrike &&
                currAddr == owner &&
                currAskPrice == askPrice &&
                currUnfilled
            ) {
                //If the current order matches the new order, we exit out because its same so no need to update.
                break;
            } else if (
                strike < currStrike ||
                (strike == currStrike && askPrice < currAskPrice)
            ) {
                _addNewOrder(owner, askPrice, posIdx, i); //Add new order into array in the first index where it has either lower strike or same strike but lower ask price.
                break;
            } else if (i == orderSize - 1) {
                openOrders.push(Order(askPrice, posIdx, owner, true)); //If at the last entry in the orders, push this at the end.
            }
        }
    }

    /*
     * Add an order to the specified index and shift every order after the index one spot to the right.
     */
    function _addNewOrder(
        address addr,
        uint256 askPrice,
        uint256 posIdx,
        uint256 index
    ) internal {
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
        currId = posIdx; //Order parameters to be added at the starting index.
        currAddr = addr;
        currAskPrice = askPrice;
        currUnfilled = true;
        for (i = index; i < openOrders.length; i++) {
            prevAskPrice = openOrders[i].askPrice; //Keep the old order at this index because it will be added to next one.
            prevId = openOrders[i].posIdx;
            prevAddr = openOrders[i].seller;
            prevUnfilled = openOrders[i].unfilled;
            openOrders[i].askPrice = currAskPrice; //Update the current order to the one before it or the new order being inserted.
            openOrders[i].posIdx = currId;
            openOrders[i].seller = currAddr;
            openOrders[i].unfilled = currUnfilled;
            currId = prevId; //Store the old order as current because it will replace the next one.
            currAddr = prevAddr;
            currAskPrice = prevAskPrice;
            currUnfilled = prevUnfilled;
        }
    }
}
