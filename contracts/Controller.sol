pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "../libs/synthetix/SafeDecimalMath.sol";
import {Settlement} from "./Settlement.sol";
import {VariancePosition} from "./VariancePosition.sol";
import {PoolInterface} from "../interfaces/PoolInterface.sol";
import {OracleInterface} from "../interfaces/OracleInterface.sol";
import {OrderbookInterface} from "../interfaces/OrderbookInterface.sol";

contract Controller is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMathUpgradeable for uint256;

    uint64 constant PAGESIZE = 1000;
    uint256 constant VARIANCE_UNIT = 1e25;
    PoolInterface private pool;
    mapping(string => address) internal deployedBooks;

    function initialize(address poolAddress) public initializer {
        OwnableUpgradeable.__Ownable_init();
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
        OrderbookInterface bookToSettle =
            OrderbookInterface(deployedBooks[bookID]);

        require(
            bookToSettle.isSettled() == false,
            "Controller: Cannot settle swaps for an already settled orderbook!"
        );
        (uint256 roundStart, uint256 roundEnd, , address bookOracle) =
            bookToSettle.getOrderbookInfo();
        require(
            roundEnd <= block.timestamp,
            "Controller: Cannot settle swaps before round has ended!"
        );

        OracleInterface oracle = OracleInterface(bookOracle);
        uint256 realizedVar = oracle.getRealized(roundStart, roundEnd);
        bookToSettle.settleOrderbook(realizedVar);
    }

    /**
     * @notice Return amount owed to user after settlement of all orderbook swaps.
     * @param bookID identifier of orderbook swap to redeem positions on
     * @param user user to return settlement for
     * @return (uint256) amount in wei owed to user
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

        uint256 settlement =
            SafeDecimalMath.fromFixed(currentBook.getUserSettlement(user));
        return settlement;
    }

    /**
     * @notice Take in user's desired position parameters and matches them with open sell orders, returns a price quote for user's position.
     * @param bookID identifier of orderbook to purchase from
     * @param varianceStrike variance strike of swap (8 fixed point precision)
     * @param positionSize units of variance to be purchased in 0.1 ETH units (8 fixed point precision)
     * @return unitsToBuy (uint256) array of size PAGESIZE units per order consumed (8 fixed point precision)
     * @return strikesToBuy (uint256) array of size PAGESIZE strike per order consumed (8 fixed point precision)
     * @return costToBuy (uint256) array of size PAGESIZE cost in wei per order consumed (8 fixed point precision)
     */
    function getQuoteForPosition(
        string memory bookID,
        uint256 varianceStrike,
        uint256 positionSize
    )
        external
        view
        onlyOnDeployedBooks(bookID)
        returns (
            uint256[PAGESIZE] memory unitsToBuy,
            uint256[PAGESIZE] memory strikesToBuy,
            uint256[PAGESIZE] memory costToBuy
        )
    {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);

        (, uint256 roundEnd, , ) = currentBook.getOrderbookInfo();
        require(
            roundEnd > block.timestamp,
            "Controller: Cannot retrieve position quote for a round that has ended!"
        );

        (unitsToBuy, strikesToBuy, costToBuy) = currentBook
            .getBuyOrderByUnitAmount(varianceStrike, positionSize);
        return (unitsToBuy, strikesToBuy, costToBuy);
    }

    event BuyOrder(address buyer, uint256 remainder);

    /**
     * @notice Take in user's funds optimistically and tries to fulfill the order size at the specified strike, returns remaining funds if order could not be filled completely
     * @param bookID identifier of orderbook to purchase from
     * @param buyer address of user purchasing the swap
     * @param varianceStrike variance strike of swap (8 fixed point precision)
     * @param payment amount given by the buyer to pay for their position.
     * @return (uint256) amount in wei returned the user for orders that could not be purchased.
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
        // convert payment to 8 fixed point precision
        uint256 fixedPayment = SafeDecimalMath.newFixed(payment);
        // convert 8 fixed point precision remainder to non decimal remainder
        uint256 remainder =
            SafeDecimalMath.fromFixed(
                currentBook.fillBuyOrderByMaxPrice(
                    buyer,
                    varianceStrike,
                    fixedPayment
                )
            );
        pool.transfer(deployedBooks[bookID], buyer, remainder);

        emit BuyOrder(buyer, remainder);
    }

    /**
     * @notice Transfer ETH from user into our pool in exchange for an equivalent long and short position for the specified swap. Submits sell order for the long position.
     * @param bookID identifier of orderbook to mint swap for
     * @param minter address of user minting the swap
     * @param varianceStrike variance strike of swap (8 fixed point precision)
     * @param askPrice asking price of the order in wei (8 fixed point precision)
     * @param positionSize units of variance to be sold in 0.1 ETH units (8 fixed point precision)
     */
    function sellSwapPosition(
        string memory bookID,
        address minter,
        uint256 varianceStrike,
        uint256 askPrice,
        uint256 positionSize
    ) external nonReentrant onlyForSender(minter) onlyOnDeployedBooks(bookID) {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);

        (, uint256 roundEnd, , ) = currentBook.getOrderbookInfo();
        require(
            roundEnd > block.timestamp,
            "Controller: Cannot mint swaps for a round that has ended!"
        );

        // calculate collateral required using 8 fixed point precision
        uint256 collateral =
            SafeDecimalMath.multiplyDecimal(positionSize, VARIANCE_UNIT);
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
        // convert 8 fixed point precision settlement to non decimal wei value
        uint256 settlement =
            SafeDecimalMath.fromFixed(
                currentBook.redeemUserSettlement(redeemer)
            );
        pool.transfer(deployedBooks[bookID], redeemer, settlement);
    }

    /**
     * @notice Get information about a deployed orderbook from its index
     * @param bookID orderbook identifier
     * @return (address) address of the orderbook
     * @return (uint256) UNIX timestamp round start of orderbook
     * @return (uint256) UNIX timestamp round end of orderbook
     * @return (uint256) starting implied variance for the round (8 fixed point precision)
     * @return (address) address of the oracle used by the orderbook
     */
    function getBookInfoByName(string memory bookID)
        external
        view
        onlyOnDeployedBooks(bookID)
        returns (
            address,
            uint256,
            uint256,
            uint256,
            address
        )
    {
        OrderbookInterface currentBook =
            OrderbookInterface(deployedBooks[bookID]);
        (
            uint256 roundStart,
            uint256 roundEnd,
            uint256 roundImpliedVariance,
            address bookOracle
        ) = currentBook.getOrderbookInfo();
        return (
            deployedBooks[bookID],
            roundStart,
            roundEnd,
            roundImpliedVariance,
            bookOracle
        );
    }
}
