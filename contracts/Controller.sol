pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libs/abdk-libraries-solidity/ABDKMath64x64.sol";
import {Orderbook} from "./Orderbook.sol";
import {Settlement} from "./Settlement.sol";
import {VariancePosition} from "./VariancePosition.sol";

contract Controller {
    /** WORK IN PROGRESS 
        MANY FUNCTIONS/INTERFACES ARE BASICALLY PSEUDO CODE SINCE OTHER COMPONENTS DO NOT EXIST YET
     */
    FundsPoolInterface public pool;
    OracleInterface public oracle;
    /// Possibly want to use OwnableUpgradeSafe modifier implemented in OZ to make contracts upgradable
    /// Opyn uses frameworks to make their contracts initializable and upgradable?
    /// as opposed to smart contracts that only start with embedded values
    Orderbook[] internal deployedBooks;

    /**
     * @notice Create a new orderbook for a new variance swap.
     * @param roundEnd UNIX timestamp for end of orderbook
     */
    function createNewSwapBook(uint256 roundStart, uint256 roundEnd) external {
        Orderbook newSwapBook =
            new OrderBook(
                roundStart,
                roundEnd,
                oracle.getLatestImpliedVariance()
            );
        deployedBooks.push(newSwapBook);
        return deployedBooks;
    }

    /**
     * @notice Settle an entire orderbook, distributing payouts for users to redeem.
     * @param bookAddress address of orderbook being settled
     */
    function settleSwapBook(address bookAddress) external {
        uint256 bookIndex = findBookIndex(bookAddress);
        require(
            bookIndex != deployedBooks.length,
            "Controller: Cannot settle an undeployed orderbook!"
        );
        Orderbook bookToSettle = deployedBooks[bookIndex];
        require(
            bookToSettle.roundEnd <= now,
            "Controller: Cannot settle swaps before round has ended!"
        );

        uint256 i = 0;
        uint256 j = 0;
        uint256 userSettlement;
        uint256 realizedVar =
            getRealizedVariance(bookToSettle.oracle, bookToSettle.roundEnd);
        for (i = 0; i < bookToSettle.userAddresses.length; i++) {
            userSettlement = 0;
            address currAddress = bookToSettle.userAddresses[i];
            UserPositions currUserPosition =
                bookToSettle.userPositions[currAddress];
            for (j = 0; j < currUserPosition.positions.length; j++) {
                Position currPosition = currUserPosition.positions[j];
                userSettlement.add(
                    calcPositionSettlement(
                        realizedVar,
                        currPosition.strike,
                        currPosition.longPosition,
                        currPosition.shortPosition
                    )
                );
            }
            bookToSettle.setUserSettlement(currAddress, userSettlement);
        }
        // Possibly we should store a settled value? Would be useful to keep track of whether an orderbook has been settled
        Orderbook.settled = true;
    }

    /**
     * @notice Transfer ETH from user into our pool in exchange for an equivalent long and short position for the specified swap. Submits sell order for the long position.
     * @param bookAddress address of orderbook to mint swap for
     * @param minter address of user minting the swap
     * @param strikeVariance variance strike of swap
     * @param positionSize units of variance to be sold (0.1 ETH units) needs to be ABDK 64.64-bit fixed point integer
     */
    function sellSwapPosition(
        address bookAddress,
        address minter,
        uint256 strikeVariance,
        int128 positionSize
    ) external {
        // call payable pool function that will transfer ETH from user to pool
        uint256 bookIndex = findBookIndex(bookAddress);
        require(
            bookIndex != deployedBooks.length,
            "Controller: Cannot mint swap for an undeployed orderbook!"
        );
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.roundEnd > now,
            "Controller: Cannot mint swaps for a round that has ended!"
        );

        // ABDK functions revolve around uint128 integers, first 64 bits are the integer, second 64 bits are the decimals
        // collateralSize is collateral in wei (positionSize * 1e17 wei (0.1 ETH))
        uint256 collateral = ABDKMath64x64.mulu(positionSize, 1e17);

        currentBook.sellOrder(minter, strikeVariance, askPrice, positionSize);
        pool.transferToPool(minter, collateral);
    }

    /**
     * @notice Transfer ETH from our pool to the user for their payout on their positions for a settled swap.
     * @param bookAddress address of orderbook swap to redeem positions on
     * @param redeemer address of user redeeming their positions
     */
    function redeemSwapPositions(address bookAddress, address redeemer)
        external
    {
        uint256 bookIndex = findBookIndex(bookAddress);
        require(
            bookIndex != deployedBooks.length,
            "Controller: Cannot redeem swap for an undeployed orderbook!"
        );
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.settled == true,
            "Controller: Cannot redeem swap, round has not been settled!"
        );

        uint256 settlement = currentBook.getUserSettlement(redeemer);
        pool.transferToUser(redeemer, settlement);
    }

    /**
     * @notice Find index of orderbook by address.
     * @param bookAddress address of orderbook being searched for
     */
    function findBookIndex(address bookAddress)
        internal
        view
        returns (uint256)
    {
        uint256 i;
        for (i = 0; i < deployedBooks.length; i++) {
            if (deployedBooks[i] == bookAddress) {
                return (i);
            }
        }
        return (deployedBooks.length);
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
    ) internal returns (uint256 memory) {
        (uint256 realizedVar, bool varFinalized) =
            oracle.getRealized(roundStart, roundEnd);
        require(
            varFinalized,
            "Settlement: Realized variance from oracle not settled yet"
        );
        return varFinalized;
    }
}
