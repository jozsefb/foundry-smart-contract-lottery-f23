# Provably Random Raffle Contract
## About

This code is to create a provably random smart contract lottery

## What do we want it do?

1. User can enter the lottery by paying for a ticket
    1. Ticket fees are going to go to the winner during the draw
2. After X period of time, the lottery will automatically draw a winner
    1. And this will be done programatically
3. Using Chainlink VFR & Chainlink automation
    1. Chainlink VFR -> Randomness
    2. Chainlink automation -> Time based trigger


## Tests

1. Write some deploy scripts
2. Write our tests
    1. Work on local chain
    2. Work on forked testnet
    3. Work on forked Mainnet
