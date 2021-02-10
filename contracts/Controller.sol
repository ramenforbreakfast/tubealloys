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
    OracleInterface public oracle;

    Orderbook[] internal deployedBooks;

    /**
     * @notice Create a new orderbook for a new variance swap.
     * @param roundEnd UNIX timestamp for end of orderbook
     */
    function createNewSwapBook(
        address oracleAddress,
        uint256 roundStart,
        uint256 roundEnd
    ) external {
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
    function settleSwapBook(uint256 bookIndex) external {
        Orderbook bookToSettle = getBookByIndex(bookIndex);
        require(
            bookToSettle.roundEnd() <= block.timestamp,
            "Controller: Cannot settle swaps before round has ended!"
        );

        uint256 i = 0;
        uint256 j = 0;
        address currAddress;
        uint256 currAddressLength;
        uint256 currStrike;
        int128 currLong;
        int128 currShort;
        uint256 settlementAmount;
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
                settlementAmount.add(
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
        bookToSettle.setSettled(true);
    }

    /**
     * @notice Transfer ETH from user into our pool in exchange for an equivalent long and short position for the specified swap. Submits sell order for the long position.
     * @param bookIndex index of orderbook to mint swap for
     * @param minter address of user minting the swap
     * @param strikeVariance variance strike of swap
     * @param askPrice asking price of the order in wei
     * @param positionSize units of variance to be sold (0.1 ETH units) needs to be ABDK 64.64-bit fixed point integer
     */
    function sellSwapPosition(
        uint256 bookIndex,
        address minter,
        uint256 strikeVariance,
        uint256 askPrice,
        int128 positionSize
    ) external {
        Orderbook currentBook = getBookByIndex(bookIndex);
        require(
            currentBook.roundEnd() > block.timestamp,
            "Controller: Cannot mint swaps for a round that has ended!"
        );

        // ABDK functions revolve around uint128 integers, first 64 bits are the integer, second 64 bits are the decimals
        // collateralSize is collateral in wei (positionSize * 1e17 wei (0.1 ETH))
        uint256 collateral = ABDKMath64x64.mulu(positionSize, 1e17);

        currentBook.sellOrder(minter, strikeVariance, askPrice, positionSize);
        //pool.transferToPool(minter, collateral);
    }

    /**
     * @notice Transfer ETH from our pool to the user for their payout on their positions for a settled swap.
     * @param bookIndex index of orderbook swap to redeem positions on
     * @param redeemer address of user redeeming their positions
     */
    function redeemSwapPositions(uint256 bookIndex, address redeemer) external {
        Orderbook currentBook = getBookByIndex(bookIndex);
        require(
            currentBook.settled() == true,
            "Controller: Cannot redeem swap, round has not been settled!"
        );

        uint256 settlement = currentBook.getUserSettlement(redeemer);
        //pool.transferToUser(redeemer, settlement);
    }

    /**
     * @notice Find index of orderbook by address.
     * @param bookIndex index of orderbook being searched for
     */
    function getBookByIndex(uint256 bookIndex)
        internal
        view
        returns (Orderbook)
    {
        require(
            bookIndex <= deployedBooks.length,
            "Controller: Cannot settle an undeployed orderbook!"
        );
        return deployedBooks[bookIndex];
    }

    /**
     * @notice Checks with oracle if realized variance value at round end date is valid.
     * @param oracleAddress address of oracle to determine variance validity from
     * @param roundEnd date that the round ends on
     */
    function isSettlementAllowed(address oracleAddress, uint256 roundEnd)
        internal
        returns (bool)
    {
        oracle = OracleInterface(oracleAddress);
        // boilerplate call to an oracle to determine if realized variance obtained is valid
        bool isRealizedFinalized = oracle.isDisputePeriodOver(roundEnd);
        return isRealizedFinalized;
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
    ) internal returns (uint256) {
        oracle = OracleInterface(oracleAddress);
        uint256 realizedVar = oracle.getRealized(roundStart, roundEnd);
        return realizedVar;
    }
}
