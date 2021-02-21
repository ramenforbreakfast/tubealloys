pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";
import {Orderbook} from "./Orderbook.sol";
import {Settlement} from "./Settlement.sol";
import {VariancePosition} from "./VariancePosition.sol";
import {OracleInterface} from "../interfaces/OracleInterface.sol";

contract Controller {
    /* WORK IN PROGRESS 
       MANY FUNCTIONS/INTERFACES ARE BASICALLY PSEUDO CODE SINCE OTHER COMPONENTS DO NOT EXIST YET
     */
    using SafeMath for uint256;

    //FundsPoolInterface public pool;

    Orderbook[] internal deployedBooks;

    modifier onlyOnDeployedBooks(uint256 bookIndex) {
        require(
            bookIndex < deployedBooks.length,
            "Controller: Cannot settle an undeployed orderbook!"
        );
        _;
    }

    /**
     * @notice Create a new orderbook for a new variance swap.
     * @param roundEnd UNIX timestamp for end of orderbook
     */
    function createNewSwapBook(
        address oracleAddress,
        uint256 roundStart,
        uint256 roundEnd
    ) external {
        OracleInterface oracle = OracleInterface(oracleAddress);
        Orderbook newSwapBook =
            new Orderbook(
                roundStart,
                roundEnd,
                oracleAddress,
                oracle.getLatestImpliedVariance()
            );
        deployedBooks.push(newSwapBook);
    }

    /**
     * @notice Settle an entire orderbook, distributing payouts for users to redeem.
     * @param bookIndex index of orderbook being settled
     */
    function settleSwapBook(uint256 bookIndex)
        external
        onlyOnDeployedBooks(bookIndex)
    {
        Orderbook bookToSettle = deployedBooks[bookIndex];
        require(
            bookToSettle.roundEnd() <= block.timestamp,
            "Controller: Cannot settle swaps before round has ended!"
        );

        uint256 i;
        uint256 j;
        address currAddress;
        uint256 currAddressLength;
        uint256 currStrike;
        int128 currLong;
        int128 currShort;
        uint256 settlementAmount = 0;
        uint256 realizedVar =
            getRealizedVariance(
                bookToSettle.bookOracle(),
                bookToSettle.roundStart(),
                bookToSettle.roundEnd()
            );
        for (i = 0; i < bookToSettle.getNumberofActiveAddresses(); i++) {
            settlementAmount = 0;
            currAddress = bookToSettle.getAddrbyIdx(i);
            currAddressLength = bookToSettle.getNumberofUserPositions(
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
        // Possibly we should store a settled value? Would be useful to keep track of whether an orderbook has been settled
        bookToSettle.settleOrderBook();
    }

    /**
     * @notice Return amount owed to user after settlement of all orderbook swaps.
     * @param bookIndex index of orderbook swap to redeem positions on
     * @param user user to return settlement for
     * @return amount in wei owed to user
     */
    function getSettlementForUser(uint256 bookIndex, address user)
        external
        view
        onlyOnDeployedBooks(bookIndex)
        returns (uint256)
    {
        Orderbook currentBook = deployedBooks[bookIndex];
        //require(
        //    currentBook.settled() == true,
        //    "Controller: Cannot query settlement amount for an unsettled orderbook!"
        //);

        uint256 settlement = currentBook.getUserSettlement(user);
        return settlement;
    }

    /**
     * @notice Take in user's desired position parameters and matches them with open sell orders, returns a price quote for user's position.
     * @param bookIndex index of orderbook to purchase from
     * @param varianceStrike variance strike of swap
     * @param positionSize units of variance to be purchased (0.1 ETH units) needs to be ABDK 64.64-bit fixed point integer
     * @return uint256 total cost in wei for position quote, int128 64.64 total amount of variance units for position quote
     */
    function getQuoteForPosition(
        uint256 bookIndex,
        uint256 varianceStrike,
        int128 positionSize
    ) external view onlyOnDeployedBooks(bookIndex) returns (uint256, int128) {
        Orderbook currentBook = deployedBooks[bookIndex];
        //require(
        //    currentBook.roundEnd() > block.timestamp,
        //    "Controller: Cannot purchase swaps for a round that has ended!"
        //);
        uint256 totalPaid;
        int128 totalUnits;
        (totalPaid, totalUnits) = currentBook.getBuyOrderbyUnitAmount(
            varianceStrike,
            positionSize
        );
        //pool.transferToPool(buyer, totalPaid);
        return (totalPaid, totalUnits);
    }

    /**
     * @notice Wrapper function to call orderbook getPosition function, returns user's position at selected index
     * @param bookIndex index of orderbook being queried
     * @param userAddress address of the user position belongs to
     * @param positionIndex index of user position
     * @return uint256 user strike, int128 64.64 user long position, int 128 64.64 user short position
     */
    function getUserPosition(
        uint256 bookIndex,
        address userAddress,
        uint256 positionIndex
    )
        external
        view
        onlyOnDeployedBooks(bookIndex)
        returns (
            uint256,
            int128,
            int128
        )
    {
        Orderbook currentBook = deployedBooks[bookIndex];
        uint256 userStrike;
        int128 userLong;
        int128 userShort;
        (userStrike, userLong, userShort) = currentBook.getPosition(
            userAddress,
            positionIndex
        );
        return (userStrike, userLong, userShort);
    }

    /**
     * @notice Take in user's desired position parameters and matches them with open sell orders, returns a price quote for user's position.
     * @param bookIndex index of orderbook to purchase from
     * @param buyer address of user purchasing the swap
     * @param varianceStrike variance strike of swap
     * @param payment amount offered by the buyer to pay for their position.
     * @return uint256 amount in wei returned the user for orders that could not be purchased.
     */
    function buySwapPosition(
        uint256 bookIndex,
        address buyer,
        uint256 varianceStrike,
        uint256 payment
    ) external onlyOnDeployedBooks(bookIndex) returns (uint256) {
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.roundEnd() > block.timestamp,
            "Controller: Cannot purchase swaps for a round that has ended!"
        );
        uint256 remainder =
            currentBook.fillBuyOrderbyMaxPrice(buyer, varianceStrike, payment);
        //pool.transferToPool(buyer, totalPaid);
        return remainder;
    }

    /**
     * @notice Transfer ETH from user into our pool in exchange for an equivalent long and short position for the specified swap. Submits sell order for the long position.
     * @param bookIndex index of orderbook to mint swap for
     * @param minter address of user minting the swap
     * @param varianceStrike variance strike of swap
     * @param askPrice asking price of the order in wei
     * @param positionSize units of variance to be sold (0.1 ETH units) needs to be ABDK 64.64-bit fixed point integer
     */
    function sellSwapPosition(
        uint256 bookIndex,
        address minter,
        uint256 varianceStrike,
        uint256 askPrice,
        int128 positionSize
    ) external onlyOnDeployedBooks(bookIndex) {
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.roundEnd() > block.timestamp,
            "Controller: Cannot mint swaps for a round that has ended!"
        );

        // ABDK functions revolve around uint128 integers, first 64 bits are the integer, second 64 bits are the decimals
        // collateralSize is collateral in wei (positionSize * 1e17 wei (0.1 ETH))
        uint256 collateral = ABDKMath64x64.mulu(positionSize, 1e17);

        currentBook.sellOrder(minter, varianceStrike, askPrice, positionSize);
        //pool.transferToPool(minter, collateral);
    }

    /**
     * @notice Transfer ETH from our pool to the user for their payout on their positions for a settled swap.
     * @param bookIndex index of orderbook swap to redeem positions on
     * @param redeemer address of user redeeming their positions
     */
    function redeemSwapPositions(uint256 bookIndex, address redeemer)
        external
        onlyOnDeployedBooks(bookIndex)
    {
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.settled() == true,
            "Controller: Cannot redeem swap, round has not been settled!"
        );

        uint256 settlement = currentBook.getUserSettlement(redeemer);
        //pool.transferToUser(redeemer, settlement);
    }

    /**
     * @notice Get information about a deployed orderbook from its index
     * @param bookIndex index of the orderbook
     * @return address of the orderbook
     * @return address of the orderbook's oracle
     * @return orderbook roundStart timestamp
     * @return orderbook roundEnd timestamp
     */
    function getBookInfoByIndex(uint256 bookIndex)
        external
        view
        onlyOnDeployedBooks(bookIndex)
        returns (
            address,
            address,
            address,
            uint256,
            uint256
        )
    {
        Orderbook currentBook = deployedBooks[bookIndex];
        return (
            address(currentBook),
            currentBook.owner(),
            currentBook.bookOracle(),
            currentBook.roundStart(),
            currentBook.roundEnd()
        );
    }

    /**
     * @notice Pulls realized variance from oracle, checks if realized value is valid.
     * @param oracleAddress address of oracle to grab realized variance from
     * @param roundStart round start date to the swap round
     * @param roundEnd round end date to the swap round
     */
    function getRealizedVariance(
        address oracleAddress,
        uint256 roundStart,
        uint256 roundEnd
    ) internal view returns (uint256) {
        OracleInterface oracle = OracleInterface(oracleAddress);
        uint256 realizedVar = oracle.getRealized(roundStart, roundEnd);
        return realizedVar;
    }
}
