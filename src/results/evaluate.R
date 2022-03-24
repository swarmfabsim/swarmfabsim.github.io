# SWILT Result Evaluation
#
# DO WE WANT TO GENERATE PLOT FILES OR JUST WATCH ON THE SCREEN?
outfiles = FALSE
#outfiles = TRUE


# PUT WORKING DIRECTORY HERE:
setwd('C:/Users/Martina Umlauft/workspace/swilt/src/results')


#### files
fnames = c("SWILT-Simulation Experiment-ICAART-ABC", "SWILT-Simulation Experiment-LARGE-1-ABC", "SWILT-Simulation Experiment-MEDIUM-1-ABC", "SWILT-Simulation Experiment-SFAB-ABC")


for(f in 1:length(fnames)) {

	tdata = read.csv( paste(fnames[f], "-table.csv", sep=""), skip = 6, stringsAsFactors = FALSE)
	colnames(tdata) <- c("run", "algo", "strategy", "cfile", "fname", "debug", "vis", "step", "avgQ", "maxQ", "minQ")

	kpis = read.table( paste(fnames[f], "-kpis.csv", sep=""), header=FALSE)
	colnames(kpis) <- c("run", "ff", "tard", "util")


	## check
	#head(tdata)
	#head(kpis)


	## results
	agg = aggregate(tdata, by = list(run.nr = tdata$run), FUN = max) # get max steps from end of each run


	if (outfiles) {sink(paste(fnames[f], "-results.txt",sep=""))}
	
	cat(paste( fnames[f], "\n" ))
	cat(paste( "avg. steps: ", mean(agg$step), "\n" ))
	cat(paste( "avg. ff: ", mean(kpis$ff), "\n" ))
	cat(paste( "avg. tard: ", mean(kpis$tard), "\n" ))
	cat(paste( "avg. util: ", mean(kpis$util), "\n\n" ))

	if (outfiles) {sink()}
}




