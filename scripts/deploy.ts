import { ethers, network } from "hardhat";
//import config from "../config";
import {parseEther} from "ethers/lib/utils";

const currentNetwork = network.name;

const main = async () => {
    console.log("Deploying to network:", currentNetwork);

    // const ContractObj = await ethers.getContractFactory("MyOApp");
    // // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy(
    //     '0x6edce65403992e310a62460808c4b910d972f10f', // endpoint
    //     '0x9645fCDc4f740FdE63388BddA9B7bDDcDE99c9Cc' // delegate
    // );
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    // const ContractObj = await ethers.getContractFactory("PancakeVeSenderV2");
    // // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy(
    //     '0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB', // veCake
    //     '0xDf4dBf6536201370F95e06A0F8a7a70fE40E388a', // pancake profile
    //     '0x1a44076050125825900e736c501f859c50fE728c', // endpoint
    //     '0x9645fCDc4f740FdE63388BddA9B7bDDcDE99c9Cc' // delegate
    // );
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    // const ContractObj = await ethers.getContractFactory("PancakeVeReceiverV2");
    // // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy(
    //     '0x1a44076050125825900e736c501f859c50fE728c', // endpoint
    //     '0x9645fCDc4f740FdE63388BddA9B7bDDcDE99c9Cc' // delegate
    // );
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    // const ContractObj = await ethers.getContractFactory("VECakeProxy");  // Arbitrum
    // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy();
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    // const ContractObj = await ethers.getContractFactory("IFODeployerV8");  // Arbitrum
    // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy();
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    // const ContractObj = await ethers.getContractFactory("PancakeProfileProxyV2"); // Arbitrum
    // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy(
    //     '0x11b63467Cf299D634d7c1A07221d78c5F08095D7', // IFODeployerV8
    //     '0x765E5f231FfD9986f888CE6F3c88bBD8FB3f04A7' // receiver
    // );
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    // const ContractObj = await ethers.getContractFactory("ICakeV3"); // Arbitrum
    // // ////// deploy ///////////////////////////
    // const obj = await ContractObj.deploy(
    //     '0x8095b52D936ACA9867c5773369adD5cbA1519632' // veCakeProxy
    // );
    // await obj.deployed();
    // console.log("Contract deployed to:", obj.address);

    const ContractObj = await ethers.getContractFactory("TestEIP1153");  // Arbitrum
    ////// deploy ///////////////////////////
    const obj = await ContractObj.deploy();
    await obj.deployed();
    console.log("Contract deployed to:", obj.address);
};
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
