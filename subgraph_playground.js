import { fetch } from 'node-fetch';

const query = `
query($network: BitcoinNetwork, $token: String){
  bitcoin(network: $network) {
    inputs(
      inputAddress: {is: $token}) {
      value
    }
    outputs( outputAddress: {is: $token}) {
      value
    }
  }
}
`;

const variables = {
    "network":"bitcoin",
    "token":"18cBEMRxXHqzWWCxZNtU91F5sbUNKhL5PX"
}

const url = "https://graphql.bitquery.io/";
const opts = {
    method: "POST",
    headers: {
        "Content-Type": "application/json",
        "X-API-KEY": "YOUR API KEY"
    },
    body: JSON.stringify({
        query,
        'variables':variables
    })
};

async function bitqueryAPICall(){
    const result = await fetch(url, opts).then(res => res.json())
    const inflow = result.data.bitcoin.inputs[0].value
    const outflow = result.data.bitcoin.outputs[0].value
    const balance = outflow - inflow
    console.log("The Balance of the particular Bitcoin wallet is", balance)
}

bitqueryAPICall()