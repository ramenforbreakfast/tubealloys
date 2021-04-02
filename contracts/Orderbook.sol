pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";
import "../libs/BokkyPooBahsRedBlackTreeLibrary/BokkyPooBahsRedBlackTreeLibrary.sol" as RedBlackTree;
import "../libs/HQ20/LinkedList.sol";
import {VariancePosition} from "./VariancePosition.sol";
import {Settlement} from "./Settlement.sol";

contract Orderbook is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    //Struct that holds information necessary to check for an open order.
    struct Order {
        uint256 totalAsk; // ask price in wei per unit for the order.
        int128 totalUnits; // total units for the order
        uint256 posIdx; // index for the seller's position.
        address seller; // address of the seller.
        bool unfilled; // has order been filled?
    }

    // Possible idea:
    // On the top level is an ordered linked list of strike prices to a binary tree of unit prices, each BT element being a linked list of orders (chronological order consumption so no sorting)
    // The searching the top level linked list of strike prices could be made reasonable to search if we set a limit to strike price precision, perhaps every 0.5 percent variance.
    // Binary tree searching of unit prices should be efficient. It is important to note that in this model, the order itself must contain the price (ask/position)
    // as it is ordered by the cost per unit of exposure.
    // Linked list of orders is easy because since we already sort by price/unit, we just need to consume starting from the first element in the linked list of orders,
    // no need to keep order within the list. We add to the back of the list as orders come in @ that price.

    mapping(address => VariancePosition.UserPositions) public userPositions; //Positions held by each seller or buyer.

    // Red Black Tree containing each strike price available in the orderbook
    RedBlackTree.Tree public strikePrices;

    // Red Black Tree for each strike price containing unit prices available for the strike
    mapping(uint256 => RedBlackTree.Tree) public unitPricesAtStrike;

    // mapping keccak256 hash of (strike and unit price) to list of orders (hashes) available at that price
    mapping(bytes32 => LinkedList.List) public ordersAtPriceAndStrike;

    // mapping user addresses to a list storing hashes of buy orders they've made NOTE: probably won't be used for v1
    mapping(address => LinkedList.List) public userBuyOrders;

    // mapping user addresses to a list storing hashes of sell orders they've made
    mapping(address => LinkedList.List) public userSellOrders;

    // mapping keccak256 hash of (order strike, unit price, seller address, and an incrementing nonce) to Order structs
    mapping(bytes32 => Order) public orders;

    uint256 private orderNonce;

    uint256 public roundStart; //round start timestamp for this orderbook

    uint256 public roundEnd; //round end timestamp for this orderbook

    uint256 public roundImpliedVariance; //Implied Variance used for this orderbook

    address public bookOracle; //Oracle used for querying variance

    address[] public userAddresses; //Addresses that hold positions

    bool public settled; //Has orderbook been settled?

    uint64 constant PAGESIZE = 1000;

    int128 constant RESOLUTION = 0x68db8bac710cb; //equal to 0.0001 in ABDKMATH64x64

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

    /*
     * Return intialized values of orderbook
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

    /*
     * Get the length of the orders maintained.
     */
    function getNumberOfOrders() external view returns (uint256) {
        return openOrders.length;
    }

    /**
     * @notice Get the ask price, position id and seller address from an order.
     * @param orderHash unique keccak256 hash for order identification
     * @return uint256 total ask price of order, uint256 index of user position, address of seller, bool of whether order has been filled
     */
    function getOrder(bytes32 orderHash)
        public
        view
        returns (
            uint256,
            uint256,
            address,
            bool
        )
    {
        Order memory currOrder = orders[orderHash];
        require(
            currOrder.seller != 0,
            "Orderbook: Tried to retrieve invalid order!"
        );
        return (
            currOrder.totalAsk,
            currOrder.posIdx,
            currOrder.seller,
            currOrder.unfilled
        );
    }

    /**
     * @notice Get the number of positions a specific address holds.
     * @param orderHash address of user
     * @return uint256 number of positions belonging to user
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
     * @return uint256 position's strike, int128 64.64 FP long position, int128 64.64 FP short position
     */
    function getPosition(address owner, uint256 index)
        public
        view
        returns (
            uint256,
            int128,
            int128
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
     * @return uint256 total amount in wei claimable by seller for order payment
     */
    function getFilledOrderPayment(address owner)
        external
        view
        returns (uint256)
    {
        return userPositions[owner].filledOrderPayment;
    }

    /**
     * @notice Display the payout from variance swap settlement.
     * @param owner address that swap settlement is owed to
     * @return uint256 total amount in wei claimable by user for swap settlement
     */
    function getUserSettlement(address owner) external view returns (uint256) {
        return userPositions[owner].userSettlement;
    }

    /**
     * @notice Get total number of address that hold positions.
     * @return uint256 number of users that hold positions on this orderbook
     */
    function getNumberOfActiveAddresses() external view returns (uint256) {
        return userAddresses.length;
    }

    /**
     * @notice Get address by index.
     * @param index index of address in userAddresses
     * @return address returned by userAddresses for the provided index
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
     * @return uint256 amount in wei redeemed by seller for order payment
     */
    function redeemFilledOrderPayment(address owner)
        external
        onlyOwner
        returns (uint256)
    {
        return VariancePosition._settleOrderPayment(userPositions[owner]);
    }

    /**
     * @notice Get the total payout for variance swaps. Set this value internally to 0 to signify the seller has received this payment.
     * @param owner address attempting to redeem settlement
     * @return uint256 amount in wei redeemed by user for swap settlement
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
     * @return bool True if orderbook has been settled, False if not
     */
    function isSettled() external view returns (bool) {
        return settled;
    }

    /**
     * @notice Set the swap settlement owed to a user, called during settleOrderBook()
     * @param owner address settlement belongs to
     * @param settlement settlement amount in wei
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
     * @param totalUnits size of position in 0.1 ETH units
     */
    function sellOrder(
        address seller,
        uint256 strike,
        uint256 totalAsk,
        int128 totalUnits
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

    /*
     * Fill a buy order from the open orders that we maintain. We go from minimum strike and fill based on the max price in ether the user wants to pay.
     */
    function fillBuyOrderByMaxPrice(
        address buyer,
        uint256 minStrike,
        uint256 maxPrice
    ) external onlyOwner returns (uint256) {
        // while RedBlackTree next() != 0 || buy amount depth reached
        require(
            roundEnd > block.timestamp,
            "Orderbook: Cannot submit buy order, round has ended!"
        );
        require(
            !settled,
            "Orderbook: Cannot submit buy order, orderbook has been settled!"
        );
        uint256 i;
        uint256 currStrike;
        int128 currLongPositionAmount;
        uint256 currAskPrice;
        int128 adjustedAmount;
        int128 unitsToFill;
        uint256 buyerPositionIndex;
        uint256 remainingPremium = maxPrice;
        uint256 initNumOfPositions = userPositions[buyer].positions.length;

        for (i = 0; i < openOrders.length; i++) {
            // Get ask price from order.
            currAskPrice = openOrders[i].totalAsk;
            // Get strike from order.
            currStrike = userPositions[openOrders[i].seller].positions[
                openOrders[i].posIdx
            ]
                .strike;
            // Get long position amount available from order.
            currLongPositionAmount = userPositions[openOrders[i].seller]
                .positions[openOrders[i].posIdx]
                .longPositionAmount;
            if (remainingPremium == 0) {
                // If we have filled already desired units from buyer, exit loop.
                break;
            } else if (openOrders[i].unfilled && currStrike >= minStrike) {
                // Check the order is still open and we are at desired minimum strike.
                unitsToFill = ABDKMath64x64.divu(
                    remainingPremium,
                    currAskPrice
                );
                if (unitsToFill <= RESOLUTION) {
                    break;
                } else if (
                    unitsToFill >=
                    ABDKMath64x64.sub(currLongPositionAmount, RESOLUTION)
                ) {
                    adjustedAmount = currLongPositionAmount;
                    openOrders[i].unfilled = false; //Signal order has been filled.
                } else {
                    adjustedAmount = unitsToFill;
                }
                // Remove the long position amount that has been filled from seller.
                VariancePosition._removeFromPosition(
                    userPositions[openOrders[i].seller],
                    adjustedAmount,
                    0,
                    0,
                    openOrders[i].posIdx
                );
                // Add payout seller gets from buyer for filling this order.
                VariancePosition._addToPosition(
                    userPositions[openOrders[i].seller],
                    currStrike,
                    0,
                    0,
                    ABDKMath64x64.mulu(adjustedAmount, currAskPrice),
                    openOrders[i].posIdx
                );
                // Find if buyer has an open position to add long position to.
                buyerPositionIndex = VariancePosition._findPositionIndex(
                    userPositions[buyer],
                    currStrike
                );
                // Add the long units to buyer position.
                VariancePosition._addToPosition(
                    userPositions[buyer],
                    currStrike,
                    adjustedAmount,
                    0,
                    0,
                    buyerPositionIndex
                );
                remainingPremium = remainingPremium.sub(
                    ABDKMath64x64.mulu(adjustedAmount, currAskPrice)
                );
            }
        }
        if (maxPrice != remainingPremium && initNumOfPositions == 0) {
            // Maintain addresses that hold positions
            userAddresses.push(buyer);
        }

        return remainingPremium;
    }

    /**
     * @notice Returns a quote of orders available in the orderbook given a minimum strike and desired swap exposure
     * @param minStrike minimum strike
     * @param unitsRequested desired amounts of unit exposure
     * @return 3 arrays of size PAGESIZE of 64.64 FP units per order consumed, uint256 strike per order consumed, uint256 cost in wei per order consumed
     */
    function getBuyOrderByUnitAmount(uint256 minStrike, int128 unitsRequested)
        external
        view
        onlyOwner
        returns (
            int128[PAGESIZE] memory,
            uint256[PAGESIZE] memory,
            uint256[PAGESIZE] memory
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
        int128 unitsLeft;
        uint256 ct = 0;
        uint256 currStrike;
        uint256 currUnitPrice;
        uint256 currOrderID;
        uint256 currOrderNext;
        Order memory currOrder;
        RedBlackTree.Tree memory _unitPricesAtStrike;
        int128[PAGESIZE] memory unitsToBuy;
        uint256[PAGESIZE] memory strikesToBuy;
        uint256[PAGESIZE] memory costOfOrders;

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
            _unitPricesAtStrike = unitPricesAtStrike[currStrike];
            currUnitPrice = RedBlackTree.first(_unitPricesAtStrike);
            // search tree starting from lowest unit price
            while (currUnitPrice != 0 || unitsLeft > 0 || ct < PAGESIZE) {
                strikeAndPriceHash = keccak256(
                    abi.encode(currStrike, currUnitPrice)
                );
                _ordersAtPriceAndStrike = ordersAtPriceAndStrike[
                    strikeAndPriceHash
                ];
                currOrderID = _ordersAtPriceAndStrike.head;
                // iterate through list of orders at unit price
                while (currOrderID != 0 || unitsLeft > 0 || ct < PAGESIZE) {
                    (, currOrderNext, currOrderHash) = LinkedList.get(
                        _ordersAtPriceAndStrike,
                        currOrderID
                    );
                    currOrder = orders[currOrderHash];
                    // if order is greater than what is left to fulfill, calculate cost to partially consume and finish
                    if (currOrder.totalUnits > unitsLeft) {
                        unitsToBuy[ct] = unitsLeft;
                        strikesToBuy[ct] = currStrike;
                        costOfOrders[ct] = ABDKMath64x64.mulu(
                            unitsLeft,
                            currUnitPrice
                        );
                        unitsLeft = 0;
                    }
                    // else add order to the query and calculate amount we still need to fulfill
                    else {
                        unitsToBuy[ct] = currOrder.totalUnits;
                        strikesToBuy[ct] = currStrike;
                        costOfOrders[ct] = currOrder.totalAsk;
                        unitsLeft = ABDKMath64x64.sub(
                            unitsLeft,
                            currOrder.totalUnits
                        );
                    }
                    ct++;
                    // find next order in list
                    currOrderID = currOrderNext;
                }
                // find next lowest unit price
                currUnitPrice = RedBlackTree.next(
                    _unitPricesAtStrike,
                    currUnitPrice
                );
            }
            // find next strike
            currStrike = RedBlackTree.next(strikePrices, currStrike);
        }
        return (unitsToBuy, strikesToBuy, costOfOrders);
    }

    /**
     * @notice Inserts a sell order into the orderbook, sorted by strike, then unit price
     * @param owner address of user making the order
     * @param strike strike of the order
     * @param totalAsk total asking amount in wei
     * @param totalUnits size of order in 0.1 ETH units
     * @param posIdx index of user position the order will be fullfilled from
     */
    function addToOrderbook(
        address owner,
        uint256 strike,
        uint256 totalAsk,
        int128 totalUnits,
        uint256 posIdx
    ) internal {
        int128 invTotalUnits;
        uint256 unitPrice;
        bytes32 strikeAndPriceHash;
        bytes32 orderHash;
        // unit price = total units / total ask
        invTotalUnits = ABDKMath64x64.inv(totalUnits);
        unitPrice = ABDKMath64x64.mulu(invTotalUnits, totalAsk);
        // calculate order hash and add order
        orderHash = keccak256(abi.encode(strike, unitPrice, owner));
        orders[orderHash] = Order(totalAsk, totalUnits, posIdx, owner, false);
        // find or insert strike
        if (RedBlackTree.exists(strikePrices, strike) == false) {
            RedBlackTree.insert(strikePrices, strike);
        }
        // find or insert price per 0.1 ETH unit for strike
        RedBlackTree.Tree storage _unitPricesAtStrike =
            unitPricesAtStrike[strike];
        if (RedBlackTree.exists(_unitPricesAtStrike, unitPrice) == false) {
            RedBlackTree.insert(_unitPricesAtStrike, unitPrice);
        }
        // navigate to list of orders at unit price and strike
        strikeAndPriceHash = keccak256(abi.encode(strike, unitPrice));
        LinkedList.List storage _ordersAtPriceAndStrike =
            ordersAtPriceAndStrike[strikeAndPriceHash];
        // add order to the end of list
        LinkedList.addHead(_ordersAtPriceAndStrike, orderHash);
        // record sell order for user
        userSellOrders[owner].addHead(orderHash);
    }

    function settleOrderbook(uint256 realizedVar) external onlyOwner {
        uint256 i;
        uint256 j;
        address currAddress;
        uint256 currAddressLength;
        uint256 currStrike;
        int128 currLong;
        int128 currShort;
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
