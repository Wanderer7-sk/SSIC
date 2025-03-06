# SSIC

The following is the main script file used. You can run it directly after modifying the corresponding parameters. The rest of the.m file is a script that implements the corresponding functions (for example, Soft_NonHTDescramer_llr.m is used for soft decontamentation).



**Main_receiver.mlx:** decode the received data files using Conv method, hard SD, soft SD and SSIC.

**Main_receiver_1.mlx:** Contains only the decoding of the Conv method and Soft SD, and saves the decoded information as a.mat file for ssicsave.mlx and NaiveMethod.mlx files.

**ssicsave.mlx:** using soft information (stored as a.mat file) for ssic.

**NaiveMethod:** using soft information (stored as a.mat file) for NaiveMethod.

**TX_WaveGen.mlx:** Generate WiFi packets for sending and receiving (MCS0-MCS7).

**plotssic.py:**  Plot per under different MCS



The stored data and associated images are stored in the rawSample folder. 

The Wireless Analyszer folder stores a number of script files related to wireless analysis and does not need to be modified.

If you would like to download our dataset, please visit the https://pan.baidu.com/s/1DbZoFxTAsE6VXL3JnaniFg?pwd=7kx5

Links to Reference Papers: https://ieeexplore.ieee.org/document/9940486
