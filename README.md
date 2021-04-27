# **Contract Deployment 🤮**
## 1. Deploy a local Hardhat network
```
npx hardhat node
```
## 2. Run deploy.js on your local node, deploy.js will default to using the first address defined in your local Hardhat node.
```
npx hardhat run --network localhost scripts/deploy.js
```
## 3. To interact with your deployed contracts, you can write your own script or transact directly via the Hardhat console via
```
npx hardhat console --network localhost
```

# **Contract Interaction Via Hardhat Console Examples 😸**
## - *Get default accounts available from the local Hardhat network*
```
const accounts = await ethers.getSigners()
```
## - *Access and Deposit 10 Ether into Pool Contract*
```
const poolContract = await ethers.getContractFactory("Pool")
const Pool = await poolContract.attach("0x7765aA8699844f308666391cfff5066f4E24BeB7")
await Pool.connect(accounts[0]).deposit({ value: ethers.utils.parseEther("10") })
> console.log((await Pool.getUserBalance(accounts[0].address)).toString())
10000000000000000000
await Pool.connect(accounts[1]).deposit({ value: ethers.utils.parseEther("10") })
> console.log((await Pool.getUserBalance(accounts[1].address)).toString())
10000000000000000000
```
## - *Access Controller to Sell a Swap*
Sell 28.5 variance units @ 130 strike for 0.05/unit

Please refer to the contracts to determine if an argument needs to be represented as a 8 fixed point number
```
const controllerContract = await ethers.getContractFactory("Controller")
const Controller = await controllerContract.attach("0x6e886E689e0AF483e8bE9B9BF48cB5Bd324CE5B9")
await Controller.connect(accounts[0].address).sellSwapPosition("ETH-120000000-1616043857-1616043902", accounts[0].address, 1.3e8, ethers.utils.parseEther("1.425"), 28.5e8) 
```

The sellSwapPosition function emits a SellOrder event which contains the address of the seller, and the ID of the order
To collect these events after you've called sellSwapPosition, you can use ethers.js event filters as shown below. 

```
let sellEventFilter = Controller.filters.SellOrder()
let sellEvent = await Controller.queryFilter(sellEventFilter, "latest")
> console.log(Number(sellEvent[0].args.orderID))
1
```
## - *Access Controller to Quote a Swap*
Get quote for 80 variance units @ 130 strike

NOTE: For 8 fixed point return values that represent wei values, use the BigNumber .div() function instead of JS built-in division because
wei values are too large for JS to handle and unlike position sizes, do not need to be decimalized (< 1 wei is insignificant)
```
results = await Controller.connect(addr3).getQuoteForPosition("ETH-120000000-1616043857-1616043902", 1.3e8, 40e8);
console.log("(" + results[0] / 1e8 + ")" + " Units Left Unmatched" + ", Units to Partially Purchase From Last Order: " + results[1] / 1e8);
orderIDS = results[2];
for (let i = 0; i < 10; i++) {
    if (orderIDS[i] != 0) {
        console.log("Order " + orderIDS[i])
        query = await Orderbook.getOrder(orderIDS[i]);
        console.log("Current Ask: " + ethers.utils.formatEther(query[2].div(1e8)) + " ETH, Current Units: " + (query[1] / 1e8).toString())
        console.log("Belonging to: " + query[0] + " @ position index: " + query[5].toString());
    }
}
```

## - *Access Controller to Buy a Swap*
Purchase 1.425 ETH of 130 strike
```
buyTx = await Controller.connect(accounts[1].address).buySwapPosition("ETH-120000000-1616043857-1616043902", accounts[1].address, 1.3e8, ethers.utils.parseEther("1.425"))
try {
    buyReceipt = await buyTx.wait();
} catch (e) {
    console.log(`Transaction Receipt Not Received!\n${e}`);
}
console.log(buyReceipt.events[0].args.remainder)
```
