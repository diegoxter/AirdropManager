# AirMan Protocol

This projects allow users to create Airdrop campaigns.

Airdrops tend to be done via importing a file from block explorers or asking users their
addressess via Social Networks. Ideally, to keep **privacy** an user shouldn't need to
give away his/her address, especially as shitcoin traps (honeypots or address snipping)
use this social engineering technique with malicious intent.

AirMan solves this as users could interact with their desired protocol airdrop
in an pseudoanonymous way; and community managing gets easier as whitelists can 
be kept in a transparent / decentralized way. 

## How does it works?

Each **AirMan** instance gets deployed by an **AdminPanel**, a small contract that can create
new instances if the owner wants to or a project manager pays the fee.

Once a project manager gets his/her own **AirMan** instance, **AirdropCampaign**s can be deployed 
allowing paid whitelists, giving away a fixed amount of tokens or splitting a pool between
every participant. Campaigns can be paused; addressess can be banned and tokens/ether can be 
retrieved by the project's manager after some time has passed (so users don't get scammed once 
they have paid).

This is a WIP and a frontend will be built once the contracts are solid enough