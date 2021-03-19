**Contract Deployment**
1. Deploy a local Hardhat network
```
npx hardhat node
```
2. Run deploy.js on your local node, deploy.js will default to using the first address defined in your local Hardhat node.
```
npx hardhat run --network localhost scripts/deploy.js
```
3. To interact with your deployed contracts, you can write your own script or transact directly via the Hardhat console via
```
npx hardhat console --network localhost
```

**Contract Interaction Via Hardhat Console Examples**
1. Get default accounts available from the local Hardhat network
```
const accounts = await ethers.getSigners()
```
2. Access and Deposit 10 Ether into Pool Contract
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
3. Access Controller to Sell a Swap
Sell 28.5 variance units @ 130 strike for 0.05/unit
ABDK conversion functions convertTo64x64 and convertFrom64x64 are available within the Hardhat console using the provided hardhat.config.js
Please refer to the contracts to determine if an argument needs to be a 64.64 fixed point number or a regular unsigned integer
```
const controllerContract = await ethers.getContractFactory("Controller")
await Controller.connect(accounts[0].address).sellSwapPosition("ETH-120-1616043857-1616043902", accounts[0].address, 130, ethers.utils.parseEther("0.05"), convertTo64x64(28.5))
```
4. Access Controller to Quote a Swap
Get quote for 80 variance units @ 130 strike
```
results = await Controller.connect(accounts[1].address).getQuoteForPosition("ETH-120-1616043857-1616043902", 130, convertTo64x64(80))
console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled")
```

5. Access Controller to Buy a Swap
Purchase 1.425 ETH of 130 strike
```
buyTx = await Controller.connect(accounts[1].address).buySwapPosition("ETH-120-1616043857-1616043902", accounts[1].address, 130, ethers.utils.parseEther("1.425"))
try {
    buyReceipt = await buyTx.wait();
} catch (e) {
    console.log(`Transaction Receipt Not Received!\n${e}`);
}
console.log(buyReceipt.events[0].args.remainder)
```