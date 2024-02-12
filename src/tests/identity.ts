import { Secp256k1KeyIdentity } from "@dfinity/identity-secp256k1";
import hdkey from "hdkey";
import bip39 from "bip39";
``;
// Completely insecure seed phrase. Do not use for any purpose other than testing.
// Resolves to "wnkwv-wdqb5-7wlzr-azfpw-5e5n5-dyxrf-uug7x-qxb55-mkmpa-5jqik-tqe"
const seed = "<SEED_PHRASES>";

export const identityFromSeed = async (phrase) => {
  const seed = await bip39.mnemonicToSeed(phrase);
  const root = hdkey.fromMasterSeed(seed);
  const addrnode = root.derive("m/44'/223'/0'/0/0");

  const address = Secp256k1KeyIdentity.fromSecretKey(addrnode.privateKey);

  return address;
};

export const identity = identityFromSeed(seed);