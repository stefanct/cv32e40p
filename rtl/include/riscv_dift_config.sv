// DIFT extension for CV32E40P
// DIFT Config Header file
//   precompiler switch to enable/disable DIFT completely during synthesis
//   defining DIFT tag bits size (type definition)
// Autor:   Jakob Sailer, Bsc
// created: 2022-02-08



// to deactivate DIFT: comment out the following line
`define DIFT_ACTIVE


// comment out the respective line to either use 1 or 4 tag bits per 32 bit
// typedef logic dift_tag_t;
typedef logic[3:0] dift_tag_t;

parameter DIFT_TAG_SIZE = $bits(dift_tag_t);
