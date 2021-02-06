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
    address oracleAddress;
    Orderbook[] internal deployedBooks;

    /**
     * @notice Create a new orderbook for a new variance swap.
     * @param roundEnd UNIX timestamp for end of orderbook
     */
    function createNewSwapBook(uint256 roundEnd) external {
        Orderbook newSwapBook =
            new OrderBook(oracle.getLatestImpliedVariance(), roundEnd);
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
        uint256 dateToSettle = bookToSettle.getRoundEnd();
        require(
            dateToSettle <= now,
            "Controller: Cannot settle swaps before round has ended!"
        );
        require(
            isSettlementAllowed(dateToSettle),
            "Controller: Price data for roundEnd timestamp has not been settled yet!"
        );

        uint256 realizedVar = getRealizedVariance(dateToSettle);
        uint256 i = 0;
        uint256 j = 0;
        for (i = 0; i < bookToSettle.userAddresses.length; i++) {
            address currAddress = bookToSettle.userAddresses[i];
            UserPositions positionsToSettle =
                bookToSettle.userPositions[currAddress];
            for (j = 0; j < positionsToSettle.length; j++) {
                settleSwapPosition(realizedVar, positionsToSettle, j);
            }
        }
        // Possibly we should store a settled value? Would be useful to keep track of whether an orderbook has been settled
        Orderbook.settled = 1;
    }

    /**
     * @notice Transfer ETH from user into our pool in exchange for an equivalent long and short position for the specified swap.
     * @param bookAddress address of orderbook to mint swap for
     * @param minter address of user minting the swap
     * @param strikeVariance variance strike of swap
     * @param collateralSize size of collateral being committed in wei
     */
    function mintSwap(
        address bookAddress,
        address minter,
        uint256 strikeVariance,
        uint256 collateralSize
    ) external {
        // call payable pool function that will transfer ETH from user to pool
        uint256 bookIndex = findBookIndex(bookAddress);
        require(
            bookIndex != deployedBooks.length,
            "Controller: Cannot mint swap for an undeployed orderbook!"
        );
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.getRoundEnd() > now,
            "Controller: Cannot mint swaps for a round that has ended!"
        );
        // ABDK functions revolve around uint128 integers, first 64 bits are the integer, second 64 bits are the decimals
        // swapSize is collateral in wei divided by 0.1 eth (1e17 wei)
        uint128 swapSize = ABDKMath64x64.divu(collateralSize, 1e17);
        // Is this function call safe? What if user does not have a position
        uint256 numberOfUserPos = currentBook.getNumberofUserPositions(minter);
        // It doesn't make sense for me to use _createPosition directly from VariancePosition library
        // Since I'm minting a swap, I need to create a position AS WELL AS assign it to a user in the OrderBook
        // This createPosition function should call _createPosition from the VariancePosition Library and then assign it to a user in userPositions
        // Ideally it should have logic to check if the user position already exists, else create a new one.
        currentBook.createPosition(
            minter,
            currentBook.userPositions,
            strikeVariance,
            swapSize
        );
        pool.transferToPool(minter, collateralSize);
    }

    /**
     * @notice Transfer ETH from our pool to the user for their payout on a settled swap.
     * @param bookAddress address of orderbook to redeem swap for
     * @param redeemer address of user redeeming the swap
     * @param positionIndex index of swap being redeemed, in my mind this would be provided from the frontend since the frontend will be listing a
     * result from a view function called on the user's positions.
     */
    function redeemSwap(
        address bookAddress,
        address redeemer,
        uint256 positionIndex
    ) external {
        uint256 bookIndex = findBookIndex(bookAddress);
        require(
            bookIndex != deployedBooks.length,
            "Controller: Cannot redeem swap for an undeployed orderbook!"
        );
        Orderbook currentBook = deployedBooks[bookIndex];
        require(
            currentBook.settled == 1,
            "Controller: Cannot redeem swap, round has not been settled!"
        );
        // Noticed that these view functions have no safety mechanism, can call on nonexistent index
        // I can solve this using the following for redeemSwap, but in mintSwap, I have to do a lot more checks
        // Here in redeemSwap, I only have to check if the swap being redeemed exists in userPositions
        // In mint, I have to check if the user already has a position on the same swap, because then I should add to that existing position
        // I then have to create a new swap if that doesn't happen.
        // IMO this checking logic shouldn't have to be done inside the controller.
        require(
            positionIndex <= currentBook.getNumberofUserPositions(redeemer),
            "Controller: Position being redeemed does not exist for the user!"
        );
        // But would prefer the view function to be designed in a way where I don't have to do that.
        (, uint128 longToRemove, uint128 shortToRemove, uint256 settlement) =
            currentBook.getPosition(redeemer, positionIndex);

        // Need a function to zero out the settlement balance owed to the user's position
        // I want to be able to zero out the settlement balance BEFORE we transfer funds to the user
        // Not sure if this will work, since I think settlement is a pointer to the actual position, so if i remove it
        // THEN transfer, the settlement transferred will be zero
        _removeFromPosition(
            currentBook.userPositions,
            positionIndex,
            longToRemove,
            shortToRemove,
            settlement
        );
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
     * @param _roundEnd date that the round ends on
     */
    function isSettlementAllowed(uint256 _roundEnd) internal returns (bool) {
        // boilerplate call to an oracle to determine if realized variance obtained is valid
        bool isRealizedFinalized = oracle.isDisputePeriodOver(_roundEnd);
        return isRealizedFinalized;
    }

    /**
     * @notice Pulls realized variance from oracle, checks if realized value is valid.
     * @param _date date to retrieve realized variance for
     */
    function getRealizedVariance(uint256 date)
        internal
        returns (uint256 memory)
    {
        (uint256 realizedVar, bool varFinalized) = oracle.getRealized(date);
        require(
            varFinalized,
            "Settlement: Realized variance from oracle not settled yet"
        );
        return varFinalized;
    }
}
