const ethers= require('ethers');

// Define provider
const provider = new ethers.providers.JsonRpcProvider('YOUR_RPC_PROVIDER_HERE');

// Define the smart contract address and ABI
// find endpoint address here: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
const LzEndpointAddress = 'END_POINT_ADDRESS_HERE';
const LzEndpointABI = [{ "inputs": [ { "internalType": "address", "name": "_oapp", "type": "address" }, { "internalType": "address", "name": "_lib", "type": "address" }, { "components": [ { "internalType": "uint32", "name": "eid", "type": "uint32" }, { "internalType": "uint32", "name": "configType", "type": "uint32" }, { "internalType": "bytes", "name": "config", "type": "bytes" } ], "internalType": "struct SetConfigParam[]", "name": "_params", "type": "tuple[]" } ],
    "name": "setConfig", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
    { "inputs": [ { "internalType": "address", "name": "oapp", "type": "address" } ], "name": "delegates", "outputs": [ { "internalType": "address", "name": "delegate", "type": "address" } ], "stateMutability": "view", "type": "function"
    }];

// Create a contract instance
const contract = new ethers.Contract(LzEndpointAddress, LzEndpointABI, provider);

// Define the addresses and parameters
// find sendlib302 and receivelib302 addresses here: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
const oappAddress = 'YOUR_OAPP_ADDRESS_HERE';
const sendLibAddress = 'SENDLIB302_ADDRESS_HERE';
const receiveLibAddress = 'RECEIVELIB302_ADDRESS_HERE';
const remoteEid = 30102; // Example target endpoint ID, Binance Smart Chain
const executorConfigType = 1; // 1 for executor
const ulnConfigType = 2; // 2 for UlnConfig

// ULN Configuration Reset Params
// DVN Mainnet Addresses https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
const confirmations = 20;
const optionalDVNCount = 0;
const requiredDVNCount = 1;
const optionalDVNThreshold = 0;
const requiredDVNs = [
    'YOUR_DVN_ADDRESS_HERE'
];
const optionalDVNs = [];

// Executor Configuration Reset Params
const maxMessageSize = 10000; // Representing no limit on message size
const executorAddress = 'YOUR_EXECUTOR_ADDRESS_HERE'; // Representing no specific executor address

async function setConfig() {
    const OAPP_DELEGATE_ADDRESS = await endpointContract.delegates(oappAddress);
    console.log({
        OAPP_DELEGATE_ADDRESS
    });

    const ulnStructConfigType =
        'tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)';
    const ulnConfigData = {
        confirmations,
        requiredDVNCount,
        optionalDVNCount,
        optionalDVNThreshold,
        requiredDVNs,
        optionalDVNs,
    };
    const ulnConfigEncoded = ethers.utils.defaultAbiCoder.encode(
        [ulnStructConfigType],
        [ulnConfigData],
    );
    console.log(ulnConfigEncoded);

    const resetConfigParamUln = {
        eid: 30102, // Replace with the target chain's endpoint ID
        configType: ulnConfigType,
        config: ulnConfigEncoded,
    };

    const executorConfigStructType = 'tuple(uint32 maxMessageSize, address executorAddress)';
    const executorConfigData = {
        maxMessageSize,
        executorAddress,
    };
    const executorConfigEncoded = ethers.utils.defaultAbiCoder.encode(
        [executorConfigStructType],
        [executorConfigData],
    );
    console.log(executorConfigEncoded);

    const resetConfigParamExecutor = {
        eid: 30102, // Replace with the target chain's endpoint ID
        configType: executorConfigType,
        config: executorConfigEncoded,
    };

    try {
        const tx1 = await endpointContract.setConfig(oappAddress, sendLibAddress, [
            resetConfigParamUln,
            resetConfigParamExecutor,
        ], {
            from: OAPP_DELEGATE_ADDRESS
        });
        console.log({tx1});

        //await tx1.wait();

        const tx2 = await endpointContract.setConfig(oappAddress, receiveLibAddress, [
            resetConfigParamUln,
        ], {
            from: OAPP_DELEGATE_ADDRESS
        });
        console.log({tx2});

        //await tx2.wait();
    } catch (error) {
        const errorData = error?.error?.error?.error?.data || error?.error?.error?.data || error?.error?.data || error?.data;
        console.log({
            errorData
        })
        if (errorData) {
            const res = await fetch(`https://www.4byte.directory/api/v1/signatures/?hex_signature=${errorData}`, {
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                },
            });

            if (res.status === 200) {
                const json = await res.json();
                const errorMessage = json.results?.[0]?.text_signature

                if (errorMessage) {
                    throw new Error(errorMessage);
                }
            }
        }

        throw error;
    }
}

// Execute the function
setConfig();
