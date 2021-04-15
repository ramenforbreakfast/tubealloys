pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {
    BokkyPooBahsRedBlackTreeLibrary as RedBlackTree
} from "../libs/BokkyPooBahsRedBlackTreeLibrary/BokkyPooBahsRedBlackTreeLibrary.sol";
import "../libs/synthetix/SafeDecimalMath.sol";
import {LinkedList} from "../libs/HQ20/LinkedList.sol";
import {VariancePosition} from "./VariancePosition.sol";
import {Settlement} from "./Settlement.sol";

contract Orderbook is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    //Struct that holds information necessary to check for an open order.
    struct Order {
        address seller; // address of the seller.
        uint256 currUnits; // current units for the order (8 fixed point precision)
        uint256 currAsk; // current ask price in wei for the entire order (8 fixed point precision)
        uint256 totalUnits; // total units for the order (8 fixed point precision)
        uint256 totalAsk; // total ask price in wei for the entire order (8 fixed point precision)
        uint256 posIdx; // index for the seller's position
        bool filled; // has order been filled?
    }
    // Any amounts in wei will only be converted back to wei in the controller for deposit/withdrawal functions

    mapping(address => VariancePosition.UserPositions) public userPositions; //Positions held by each seller or buyer.

    // Red Black Tree containing each strike price available in the orderbook
    RedBlackTree.Tree public strikePrices;

    // Red Black Tree for each strike price containing unit prices available for the strike
    mapping(uint256 => RedBlackTree.Tree) public unitPricesAtStrikes;

    // mapping keccak256 hash of (strike and unit price) to list of orders (hashes) available at that price
    mapping(bytes32 => LinkedList.List) public ordersAtPricesAndStrikes;

    // mapping user addresses to a list storing hashes of buy orders they've made NOTE: probably won't be used for v1
    mapping(address => LinkedList.List) public userBuyOrders;

    // mapping user addresses to a list storing hashes of sell orders they've made
    mapping(address => LinkedList.List) public userSellOrders;

    // mapping keccak256 hash of (order strike, unit price, seller address, and an incrementing nonce) to Order structs
    mapping(bytes32 => Order) public orders;

    uint256 private orderNonce;

    uint256 public roundStart; //round start timestamp for this orderbook

    uint256 public roundEnd; //round end timestamp for this orderbook

    uint256 public roundImpliedVariance; //Implied Variance used for this orderbook (8 fixed point precision)

    address public bookOracle; //Oracle used for querying variance

    address[] public userAddresses; //Addresses that hold positions

    bool public settled; //Has orderbook been settled?

    uint64 constant PAGESIZE = 1000;

    //int128 constant RESOLUTION = 0x68db8bac710cb; //equal to 0.0001 in ABDKMATH64x64

    function initialize(
        uint256 startTimestamp,
        uint256 endTimestamp,
        address oracle,
        uint256 impliedVariance
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        orderNonce = 0;
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

    /**
     * @notice Return intialized values of orderbook
     * @return (uint256) UNIX timestamp round start of orderbook
     * @return (uint256) UNIX timestamp round end of orderbook
     * @return (uint256) starting implied variance for the round (8 fixed point precision)
     * @return (address) address of the oracle used by the orderbook
     */
    function getOrderbookInfo()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            address
        )
    {
        return (roundStart, roundEnd, roundImpliedVariance, bookOracle);
    }

    /**
     * @notice Get the ask price, position id and seller address from an order.
     * @param orderHash unique keccak256 hash for order identification
     * @return (address) address of the seller
     * @return (uint256) current amount of units left in the order (8 fixed point precision)
     * @return (uint256) current asking value left in the order in wei (8 fixed point precision)
     * @return (uint256) total amount of units order began with (8 fixed point precision)
     * @return (uint256) total asking value order began with in wei (8 fixed point precision)
     * @return (uint256) index of position associated with the seller 
     * @return (bool) true if order has been filled, false if unfilled.
     */
    function getOrder(bytes32 orderHash)
        public
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        Order memory currOrder = orders[orderHash];
        require(
            currOrder.seller != address(0),
            "Orderbook: Tried to retrieve invalid order!"
        );
        return (
            currOrder.seller,
            currOrder.currUnits,
            currOrder.currAsk,
            currOrder.totalUnits,
            currOrder.totalAsk,
            currOrder.posIdx,
            currOrder.filled
        );
    }

    /**
     * @notice Get the number of positions a specific address holds.
     * @param addr address of user
     * @return (uint256) number of positions belonging to user
     */
    function getNumberOfUserPositions(address addr)
        external
        view
        returns (uint256)
    {
        return userPositions[addr].positions.length;
    }

    /**
     * @notice Get the position given an address and position index.
     * @param owner address of position owner
     * @param index index of owner's position
     * @return (uint256) position's strike (8 fixed point precision)
     * @return (uint256) long position (8 fixed point precision)
     * @return (uint256) short position (8 fixed point precision)
     */
    function getPosition(address owner, uint256 index)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(
            index < userPositions[owner].positions.length,
            "Orderbook: Invalid user position index!"
        );
        VariancePosition.Position memory currPosition =
            userPositions[owner].positions[index];
        return (
            currPosition.strike,
            currPosition.longPositionAmount,
            currPosition.shortPositionAmount
        );
    }

    /**
     * @notice Display the payout from filled orders for a seller.
     * @param owner seller that payment is owed to
     * @return (uint256) total amount in wei claimable by seller for order payment (8 fixed point precision)
     */
    function getOrderPayments(address owner) external view returns (uint256) {
        return userPositions[owner].orderPayments;
    }

    /**
     * @notice Display the payout from variance swap settlement.
     * @param owner address that swap settlement is owed to
     * @return (uint256) total amount in wei claimable by user for swap settlement (8 fixed point precision)
     */
    function getUserSettlement(address owner) external view returns (uint256) {
        return userPositions[owner].userSettlement;
    }

    /**
     * @notice Get total number of address that hold positions.
     * @return (uint256) number of users that hold positions on this orderbook
     */
    function getNumberOfActiveAddresses() external view returns (uint256) {
        return userAddresses.length;
    }

    /**
     * @notice Get address by index.
     * @param index index of address in userAddresses
     * @return (address) returned by userAddresses for the provided index
     */
    function getAddrByIdx(uint256 index) external view returns (address) {
        require(
            index < userAddresses.length,
            "Orderbook: Invalid index for user addresses!"
        );
        return userAddresses[index];
    }

    /**
     * @notice Get the payout from filled orders for a seller. Set this value internally to 0 to signify the seller has received this payment.
     * @param owner address attempting to redeem payment
     * @return (uint256) amount in wei redeemed by seller for order payment (8 fixed point precision)
     */
    function redeemOrderPayments(address owner)
        external
        onlyOwner
        returns (uint256)
    {
        return VariancePosition._settleOrderPayments(userPositions[owner]);
    }

    /**
     * @notice Get the total payout for variance swaps. Set this value internally to 0 to signify the seller has received this payment.
     * @param owner address attempting to redeem settlement
     * @return (uint256) amount in wei redeemed by user for swap settlement (8 fixed point precision)
     */
    function redeemUserSettlement(address owner)
        external
        onlyOwner
        returns (uint256)
    {
        require(
            settled,
            "Orderbook: Cannot redeem user settlement if orderbook has not been settled!"
        );
        return VariancePosition._redeemUserSettlement(userPositions[owner]);
    }

    /**
     * @notice Retrieve settlement status of orderbook
     * @return (bool) True if orderbook has been settled, False if not
     */
    function isSettled() external view returns (bool) {
        return settled;
    }

    /**
     * @notice Set the swap settlement owed to a user, called during settleOrderBook()
     * @param owner address settlement belongs to
     * @param settlement settlement amount in wei (8 fixed point precision)
     */
    function setUserSettlement(address owner, uint256 settlement) internal {
        require(
            !settled,
            "Orderbook: Cannot modify user settlement on an already settled orderbook!"
        );
        VariancePosition._setUserSettlement(userPositions[owner], settlement);
    }

    /**
     * @notice Open a sell order for a specific strike and ask price.
     * @param seller address of seller
     * @param strike strike of swap being sold
     * @param totalAsk total asking amount in wei
     * @param totalUnits size of position in 0.1 ETH units (8 fixed point precision)
     */
    function sellOrder(
        address seller,
        uint256 strike,
        uint256 totalAsk,
        uint256 totalUnits
    ) external onlyOwner {
        require(
            roundEnd > block.timestamp,
            "Orderbook: Cannot submit sell order, round has ended!"
        );
        require(
            !settled,
            "Orderbook: Cannot submit sell order, orderbook has been settled!"
        );
        require(totalAsk != 0, "Orderbook: totalAsk cannot be zero!");
        require(totalUnits != 0, "Orderbook: totalUnits cannot be zero!");
        require(strike != 0, "Orderbook: strike cannot be zero!");
        uint256 index;
        uint256 initNumOfPositions = userPositions[seller].positions.length;

        // Find if the seller already has a position at this strike. Otherwise, get the index for a new position to be created.
        index = VariancePosition._findPositionIndex(
            userPositions[seller],
            strike
        );
        // Create or add to an existing position for the seller.
        VariancePosition._addToPosition(
            userPositions[seller],
            strike,
            totalUnits,
            totalUnits,
            0,
            index
        );
        // Add this new sell order to the orderbook.
        addToOrderbook(seller, strike, totalAsk, totalUnits, index);
        // Maintain addresses that hold positions
        if (initNumOfPositions == 0) {
            userAddresses.push(seller);
        }
    }

    /**
     * @notice Fulfill a buy order determined by minimum strike and an amount the user is willing to spend.
     * @param buyer address of buyer
     * @param minStrike minimum strike (8 fixed point precision)
     * @param amountToSpend amount user is wlling to spend in wei (8 fixed point precision)
     * @return (uint256) amount leftover that could not be fulfilled in wei (8 fixed point precision)
     */
    function fillBuyOrderByMaxPrice(
        address buyer,
        uint256 minStrike,
        uint256 amountToSpend
    ) external onlyOwner returns (uint256) {
        require(
            roundEnd > block.timestamp,
            "Orderbook: Cannot submit buy order, round has ended!"
        );
        require(
            !settled,
            "Orderbook: Cannot submit buy order, orderbook has been settled!"
        );

        bytes32 currOrderHash;
        bytes32 strikeAndPriceHash;
        uint256 longToAdd;
        uint256 currUnitPrice;
        uint256 currOrderID;
        uint256 tempNext;
        uint256 unitsBought;
        uint256 posIdx;

        // Had to cut down on the amount of variables used compared to the quoting function, harming readability, due to stack space limitations.
        // Maintain addresses that hold positions
        if (userPositions[buyer].positions.length == 0) {
            userAddresses.push(buyer);
        }

        // start with the desired strike if it exists, else find the next available strike
        if (RedBlackTree.exists(strikePrices, minStrike) == false) {
            minStrike = RedBlackTree.next(strikePrices, minStrike);
        }
        // search through orderbook until all units matched OR query size exceeds PAGESIZE
        // search strikes starting from minStrike
        while (minStrike != 0 || amountToSpend > 0) {
            // reset long position to add to buyer for every strike
            longToAdd = 0;
            currUnitPrice = RedBlackTree.first(unitPricesAtStrikes[minStrike]);
            // search tree starting from lowest unit price
            while (currUnitPrice != 0 || amountToSpend > 0) {
                strikeAndPriceHash = keccak256(
                    abi.encode(minStrike, currUnitPrice)
                );
                currOrderID = ordersAtPricesAndStrikes[strikeAndPriceHash].head;
                // iterate through list of orders at unit price
                while (currOrderID != 0 || amountToSpend > 0) {
                    (, tempNext, currOrderHash) = LinkedList.get(
                        ordersAtPricesAndStrikes[strikeAndPriceHash],
                        currOrderID
                    );
                    // if order is greater than what is left to fulfill, calculate cost to partially consume
                    if (orders[currOrderHash].currAsk > amountToSpend) {
                        // calculate number of units left in the order
                        unitsBought = SafeDecimalMath.multiplyDecimal(
                            orders[currOrderHash].currUnits,
                            SafeDecimalMath.divideDecimal(
                                amountToSpend,
                                orders[currOrderHash].currAsk
                            )
                        );
                        orders[currOrderHash].currUnits = orders[currOrderHash]
                            .currUnits
                            .sub(unitsBought);
                        // calculate new total value of order in wei
                        orders[currOrderHash].currAsk = orders[currOrderHash]
                            .currAsk
                            .sub(amountToSpend);
                        // set seller position changes and payment owed
                        longToAdd = longToAdd.add(unitsBought);
                        // remove the sold long position from the seller's balances.
                        VariancePosition._removeFromPosition(
                            userPositions[orders[currOrderHash].seller],
                            unitsBought,
                            0,
                            0,
                            orders[currOrderHash].posIdx
                        );
                        // add payout seller gets from buyer for filling this order.
                        VariancePosition._addToPosition(
                            userPositions[orders[currOrderHash].seller],
                            minStrike,
                            0,
                            0,
                            amountToSpend,
                            orders[currOrderHash].posIdx
                        );
                        // buy order has been fulfilled
                        amountToSpend = 0;
                    }
                    // else consume the order and delete the order from the linked list (do not delete from mapping of all orders)
                    else {
                        // remove order from list of orders at specified price and strike
                        LinkedList.remove(
                            ordersAtPricesAndStrikes[strikeAndPriceHash],
                            currOrderID
                        );
                        // set buyer position changes
                        longToAdd = longToAdd.add(
                            orders[currOrderHash].currUnits
                        );
                        // subtract value of current order from remaining we need to fulfill
                        amountToSpend = amountToSpend.sub(
                            orders[currOrderHash].currAsk
                        );
                        // remove the sold long position from the seller's balances.
                        VariancePosition._removeFromPosition(
                            userPositions[orders[currOrderHash].seller],
                            orders[currOrderHash].currUnits,
                            0,
                            0,
                            orders[currOrderHash].posIdx
                        );
                        // add payout seller gets from buyer for filling this order.
                        VariancePosition._addToPosition(
                            userPositions[orders[currOrderHash].seller],
                            minStrike,
                            0,
                            0,
                            orders[currOrderHash].currAsk,
                            orders[currOrderHash].posIdx
                        );
                        // zero out the order
                        orders[currOrderHash].filled = true;
                        orders[currOrderHash].currUnits = 0;
                        orders[currOrderHash].currAsk = 0;
                    }
                    // find next order in list
                    currOrderID = tempNext;
                }
                // orders at this unit price have been consumed, delete it and move to the next one
                tempNext = RedBlackTree.next(
                    unitPricesAtStrikes[minStrike],
                    currUnitPrice
                );
                if (currOrderID == 0) {
                    RedBlackTree.remove(
                        unitPricesAtStrikes[minStrike],
                        currUnitPrice
                    );
                }
                currUnitPrice = tempNext;
            }
            // orders at this strike have been consumed, delete it and move to the next one
            tempNext = RedBlackTree.next(strikePrices, minStrike);
            if (currUnitPrice == 0) {
                RedBlackTree.remove(strikePrices, minStrike);
            }
            posIdx = VariancePosition._findPositionIndex(userPositions[buyer], minStrike);
            // add the long position for the buyer at the current strike.
            VariancePosition._addToPosition(
                userPositions[buyer],
                minStrike,
                longToAdd,
                0,
                0,
                posIdx
            );
            minStrike = tempNext;
        }
        return amountToSpend;
    }

    /**
     * @notice Returns a quote of orders available in the orderbook given a minimum strike and desired swap exposure
     * @param minStrike minimum strike (8 fixed point precision)
     * @param unitsRequested desired amounts of unit exposure (8 fixed point precision)
     * @return unitsToBuy (uint256) array of size PAGESIZE (8 fixed point precision) units per order consumed
     * @return strikesToBuy (uint256) array of size PAGESIZE (8 fixed point precision) strike per order consumed
     * @return costToBuy (uint256) array of size PAGESIZE (8 fixed point precision) cost in wei per order consumed
     */
    function getBuyOrderByUnitAmount(uint256 minStrike, uint256 unitsRequested)
        external
        view
        onlyOwner
        returns (
            uint256[PAGESIZE] memory unitsToBuy,
            uint256[PAGESIZE] memory strikesToBuy,
            uint256[PAGESIZE] memory costToBuy
        )
    {
        require(
            roundEnd > block.timestamp,
            "Orderbook: Cannot get quote, round has ended!"
        );
        require(
            !settled,
            "Orderbook: Cannot get quote, orderbook has been settled!"
        );

        bytes32 currOrderHash;
        bytes32 strikeAndPriceHash;
        uint256 ct = 0;
        uint256 unitsLeft;
        uint256 currStrike;
        uint256 currUnitPrice;
        uint256 currOrderID;
        uint256 currOrderNext;

        unitsLeft = unitsRequested;
        // start with the desired strike if it exists, else find the next available strike
        if (RedBlackTree.exists(strikePrices, minStrike) == false) {
            currStrike = RedBlackTree.next(strikePrices, minStrike);
        } else {
            currStrike = minStrike;
        }
        // search through orderbook until all units matched OR query size exceeds PAGESIZE
        // search strikes starting from minStrike
        while (currStrike != 0 || unitsLeft > 0 || ct < PAGESIZE) {
            currUnitPrice = RedBlackTree.first(unitPricesAtStrikes[currStrike]);
            // search tree starting from lowest unit price
            while (currUnitPrice != 0 || unitsLeft > 0 || ct < PAGESIZE) {
                strikeAndPriceHash = keccak256(
                    abi.encode(currStrike, currUnitPrice)
                );
                currOrderID = ordersAtPricesAndStrikes[strikeAndPriceHash].head;
                // iterate through list of orders at unit price
                while (currOrderID != 0 || unitsLeft > 0 || ct < PAGESIZE) {
                    (, currOrderNext, currOrderHash) = LinkedList.get(
                        ordersAtPricesAndStrikes[strikeAndPriceHash],
                        currOrderID
                    );
                    // if order is greater than what is left to fulfill, calculate cost to partially consume and finish
                    if (orders[currOrderHash].currUnits > unitsLeft) {
                        unitsToBuy[ct] = unitsLeft;
                        strikesToBuy[ct] = currStrike;
                        costToBuy[ct] = unitsLeft.mul(currUnitPrice);
                        unitsLeft = 0;
                    }
                    // else add order to the query and calculate amount we still need to fulfill
                    else {
                        unitsToBuy[ct] = orders[currOrderHash].currUnits;
                        strikesToBuy[ct] = currStrike;
                        costToBuy[ct] = orders[currOrderHash].currAsk;
                        unitsLeft = unitsLeft.sub(
                            orders[currOrderHash].currUnits
                        );
                    }
                    ct++;
                    // find next order in list
                    currOrderID = currOrderNext;
                }
                // find next lowest unit price
                currUnitPrice = RedBlackTree.next(
                    unitPricesAtStrikes[currStrike],
                    currUnitPrice
                );
            }
            // find next strike
            currStrike = RedBlackTree.next(strikePrices, currStrike);
        }
        return (unitsToBuy, strikesToBuy, costToBuy);
    }

    /**
     * @notice Inserts a sell order into the orderbook, sorted by strike, then unit price
     * @param owner address of user making the order
     * @param strike strike of the order (8 fixed point precision)
     * @param totalAsk total asking amount in wei (8 fixed point precision)
     * @param totalUnits size of order in 0.1 ETH units (8 fixed point precision)
     * @param posIdx index of user position the order will be fullfilled from
     */
    function addToOrderbook(
        address owner,
        uint256 strike,
        uint256 totalAsk,
        uint256 totalUnits,
        uint256 posIdx
    ) internal {
        uint256 unitPrice;
        bytes32 orderHash;
        // unit price = total ask / total units
        unitPrice = totalAsk.div(totalUnits);
        // calculate order hash and add order
        orderHash = keccak256(abi.encode(strike, unitPrice, owner));
        orders[orderHash] = Order(
            owner,
            totalUnits,
            totalAsk,
            totalUnits,
            totalAsk,
            posIdx,
            false
        );
        // find or insert strike
        if (RedBlackTree.exists(strikePrices, strike) == false) {
            RedBlackTree.insert(strikePrices, strike);
        }
        // find or insert price per 0.1 ETH unit for strike
        RedBlackTree.Tree storage unitPricesAtStrike =
            unitPricesAtStrikes[strike];
        if (RedBlackTree.exists(unitPricesAtStrike, unitPrice) == false) {
            RedBlackTree.insert(unitPricesAtStrike, unitPrice);
        }
        // navigate to list of orders at unit price and strike
        LinkedList.List storage ordersAtPriceAndStrike =
            ordersAtPricesAndStrikes[keccak256(abi.encode(strike, unitPrice))];
        // add order to the end of list
        LinkedList.addHead(ordersAtPriceAndStrike, orderHash);
        // record sell order for user
        LinkedList.addHead(userSellOrders[owner], orderHash);
    }

    /**
     * @notice Settles all positions on orderbook after round ends
     * @param realizedVar realized variance of the round (8 fixed point precision)
     */
    function settleOrderbook(uint256 realizedVar) external onlyOwner {
        uint256 i;
        uint256 j;
        address currAddress;
        uint256 currAddressLength;
        uint256 currStrike;
        uint256 currLong;
        uint256 currShort;
        uint256 settlementAmount;
        for (i = 0; i < userAddresses.length; i++) {
            settlementAmount = 0;
            currAddress = userAddresses[i];
            currAddressLength = userPositions[currAddress].positions.length;

            for (j = 0; j < currAddressLength; j++) {
                (currStrike, currLong, currShort) = getPosition(currAddress, j);
                settlementAmount = settlementAmount.add(
                    Settlement.calcPositionSettlement(
                        realizedVar,
                        currStrike,
                        currLong,
                        currShort
                    )
                );
            }
            setUserSettlement(currAddress, settlementAmount);
        }
        settled = true;
    }
}
