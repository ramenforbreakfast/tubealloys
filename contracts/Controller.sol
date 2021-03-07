pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";
import {Settlement} from "./Settlement.sol";
import {VariancePosition} from "./VariancePosition.sol";
import {PoolInterface} from "../interfaces/PoolInterface.sol";
import {OracleInterface} from "../interfaces/OracleInterface.sol";
import {OrderbookInterface} from "../interfaces/OrderbookInterface.sol";

contract Controller is Ownable, ReentrancyGuard {
    /* WORK IN PROGRESS 
       MANY FUNCTIONS/INTERFACES ARE BASICALLY PSEUDO CODE SINCE OTHER COMPONENTS DO NOT EXIST YET
     */
    using SafeMath for uint256;

    //FundsPoolInterface public pool;

    uint64 constant PAGESIZE = 1000;
    PoolInterface private pool;
    mapping(string => address) internal deployedBooks;

    constructor(address poolAddress) {
        pool = PoolInterface(poolAddress);
    }

    modifier onlyForSender(address sender) {
        require(
            msg.sender == sender,
            "Controller: Cannot perform operation for another user!"
        );
        _;
    }

    modifier onlyOnDeployedBooks(string memory bookID) {
        require(
            deployedBooks[bookID] != address(0),
            "Controller: Cannot perform operation on undeployed orderbook!"
        );
        _;
    }

    /**
     * @notice Changes pool contract in use by the controller
     * @param poolAddress pool contract to be used by controller
     */
    function setNewPool(address poolAddress) external onlyOwner nonReentrant {
        pool = PoolInterface(poolAddress);
    }

    /**
     * @notice Adds a new orderbook address to the mapping of deployed orderbook contracts
     * @param bookID string for identifying orderbook i.e. ETH-121-20210101-20210201
     * @param newBookAddress address of book to add
     */
    function addNewSwapBook(string memory bookID, address newBookAddress)
        external
        onlyOwner
        nonReentrant
    {
        deployedBooks[bookID] = newBookAddress;
    }

    /**
     * @notice Settle an entire orderbook, distributing payouts for users to redeem.
     * @param bookID index of orderbook being settled
     */
    function settleSwapBook(string memory bookID)
        external
        nonReentrant
        onlyOnDeployedBooks(bookID)
    {
        uint256 i;
        uint256 j;
        address currAddress;
        uint256 currAddressLength;
        uint256 currStrike;
        int128 currLong;
        int128 currShort;
        uint256 settlementAmount;

        OrderbookInterface bookToSettle =
            OrderbookInterface(deployedBooks[bookID]);

        require(
            bookToSettle.isSettled() == false,
            "Controller: Cannot settle swaps for an already settled orderbook!"
        );
        (uint256 roundStart, uint256 roundEnd, address bookOracle, ) =
            bookToSettle.getOrderbookInfo();
        require(
            roundEnd <= block.timestamp,
            "Controller: Cannot settle swaps before round has ended!"
        );

        OracleInterface oracle = OracleInterface(bookOracle);
        uint256 realizedVar = oracle.getRealized(roundStart, roundEnd);

        for (i = 0; i < bookToSettle.getNumberOfActiveAddresses(); i++) {
            settlementAmount = 0;
            currAddress = bookToSettle.getAddrByIdx(i);
            currAddressLength = bookToSettle.getNumberOfUserPositions(
                currAddress
            );
            for (j = 0; j < currAddressLength; j++) {
                (currStrike, currLong, currShort) = bookToSettle.getPosition(
                    currAddress,
                    j
                );
                settlementAmount = settlementAmount.add(
                    Settlement.calcPositionSettlement(
                        realizedVar,
                        currStrike,
                        currLong,
                        currShort
                    )
                );
            }
            bookToSettle.setUserSettlement(currAddress, settlementAmount);
        }
        bookToSettle.settleOrderbook();
    }

    /**
     * @notice Return amount owed to user after settlement of all orderbook swaps.
     * @param bookID identifier of orderbook swap to redeem positions on
     * @param user user to return settlement for
     * @return amount in wei owed to user
     */
    function getSettlementForUser(string memory bookID, address user)
        external
        view
        onlyOnDeployedBooks(bookID)
        returns (uint256)
    {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);

        require(
            currentBook.isSettled() == true,
            "Controller: Cannot query settlement amount for an unsettled orderbook!"
        );

        uint256 settlement = currentBook.getUserSettlement(user);
        return settlement;
    }

    /**
     * @notice Take in user's desired position parameters and matches them with open sell orders, returns a price quote for user's position.
     * @param bookID identifier of orderbook to purchase from
     * @param varianceStrike variance strike of swap
     * @param positionSize units of variance to be purchased (0.1 ETH units) needs to be ABDK 64.64-bit fixed point integer
     * @return uint256 total cost in wei for position quote, int128 64.64 total amount of variance units for position quote
     */
    function getQuoteForPosition(
        string memory bookID,
        uint256 varianceStrike,
        int128 positionSize
    ) external view onlyOnDeployedBooks(bookID) returns (uint256, int128) {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);

        (, uint256 roundEnd, , ) = currentBook.getOrderbookInfo();
        require(
            roundEnd > block.timestamp,
            "Controller: Cannot retrieve position quote for a round that has ended!"
        );

        uint256 totalPaid;
        int128 totalUnits;
        int128[PAGESIZE] memory unitsToBuy;
        uint256[PAGESIZE] memory strikesToBuy;
        (totalPaid, totalUnits, unitsToBuy, strikesToBuy) = currentBook
            .getBuyOrderByUnitAmount(varianceStrike, positionSize);
        //pool.transferToPool(buyer, totalPaid);
        return (totalPaid, totalUnits);
    }

    /**
     * @notice Take in user's funds optimistically and tries to fulfill the order size at the specified strike, returns remaining funds if order could not be filled completely
     * @param bookID identifier of orderbook to purchase from
     * @param buyer address of user purchasing the swap
     * @param varianceStrike variance strike of swap
     * @param payment amount given by the buyer to pay for their position.
     * @return uint256 amount in wei returned the user for orders that could not be purchased.
     */
    function buySwapPosition(
        string memory bookID,
        address buyer,
        uint256 varianceStrike,
        uint256 payment
    )
        external
        nonReentrant
        onlyForSender(buyer)
        onlyOnDeployedBooks(bookID)
        returns (uint256)
    {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);

        (, uint256 roundEnd, , ) = currentBook.getOrderbookInfo();
        require(
            roundEnd > block.timestamp,
            "Controller: Cannot purchase swaps for a round that has ended!"
        );

        require(
            pool.getUserBalance(buyer) >= payment,
            "Controller: User has insufficient funds to purchase swaps!"
        );

        pool.transfer(buyer, deployedBooks[bookID], payment);
        uint256 remainder =
            currentBook.fillBuyOrderByMaxPrice(buyer, varianceStrike, payment);
        pool.transfer(deployedBooks[bookID], buyer, remainder);

        return remainder;
    }

    /**
     * @notice Transfer ETH from user into our pool in exchange for an equivalent long and short position for the specified swap. Submits sell order for the long position.
     * @param bookID identifier of orderbook to mint swap for
     * @param minter address of user minting the swap
     * @param varianceStrike variance strike of swap
     * @param askPrice asking price of the order in wei
     * @param positionSize units of variance to be sold (0.1 ETH units) needs to be ABDK 64.64-bit fixed point integer
     */
    function sellSwapPosition(
        string memory bookID,
        address minter,
        uint256 varianceStrike,
        uint256 askPrice,
        int128 positionSize
    ) external nonReentrant onlyForSender(minter) onlyOnDeployedBooks(bookID) {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);

        (, uint256 roundEnd, , ) = currentBook.getOrderbookInfo();
        require(
            roundEnd > block.timestamp,
            "Controller: Cannot mint swaps for a round that has ended!"
        );

        // ABDK functions revolve around uint128 integers, first 64 bits are the integer, second 64 bits are the decimals
        // collateralSize is collateral in wei (positionSize * 1e17 wei (0.1 ETH))
        uint256 collateral = ABDKMath64x64.mulu(positionSize, 1e17);
        require(
            pool.getUserBalance(minter) >= collateral,
            "Controller: User has insufficient funds to collateralize swaps!"
        );

        pool.transfer(minter, deployedBooks[bookID], collateral);
        currentBook.sellOrder(minter, varianceStrike, askPrice, positionSize);
    }

    /**
     * @notice Transfer ETH from our pool to the user for their payout on their positions for a settled swap.
     * @param bookID identifier of orderbook swap to redeem positions on
     * @param redeemer address of user redeeming their positions
     */
    function redeemSwapPositions(string memory bookID, address redeemer)
        external
        nonReentrant
        onlyForSender(redeemer)
        onlyOnDeployedBooks(bookID)
    {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);
        require(
            currentBook.isSettled() == true,
            "Controller: Cannot redeem swap before round has been settled!"
        );

        uint256 settlement = currentBook.redeemUserSettlement(redeemer);
        pool.transfer(deployedBooks[bookID], redeemer, settlement);
    }

    /**
     * @notice Get information about a deployed orderbook from its index
     * @param bookID orderbook identifier
     * @return address of the orderbook
     * @return orderbook roundStart timestamp
     * @return orderbook roundEnd timestamp
     * @return address of the orderbook's oracle
     * @return starting implied variance of round
     */
    function getBookInfoByName(string memory bookID)
        external
        view
        onlyOnDeployedBooks(bookID)
        returns (
            address,
            uint256,
            uint256,
            address,
            uint256
        )
    {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);
        (
            uint256 roundStart,
            uint256 roundEnd,
            address bookOracle,
            uint256 roundImpliedVariance
        ) = currentBook.getOrderbookInfo();
        return (
            deployedBooks[bookID],
            roundStart,
            roundEnd,
            bookOracle,
            roundImpliedVariance
        );
    }
}
