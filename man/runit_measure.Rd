% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/runit_measure.R
\name{runit_measure}
\alias{runit_measure}
\alias{runit_measure-spatPomp}
\alias{runit_measure,spatPomp-method}
\title{Random draw from the measurement model for one unit}
\usage{
\S4method{runit_measure}{spatPomp}(object, x, unit, time, params, log = FALSE)
}
\arguments{
\item{object}{An object of class \code{spatPomp}}

\item{x}{A state vector for all units}

\item{unit}{The unit for which to simulate an observation}

\item{time}{The time for which to simulate an observation}

\item{params}{parameters to use to simulate an observation}

\item{log}{logical; should the density be returned on log scale?}
}
\value{
A matrix with the simulated observation corresponding to state
\code{x} and unit \code{unit} with parameter set \code{params}.
}
\description{
\code{runit_measure} simulates a unit's observation given the entire state
}
\examples{
# Complete examples are provided in the package tests
\dontrun{
b <- bm(U=3)
s <- states(b)[,1,drop=FALSE]
rownames(s) -> rn
dim(s) <- c(3,1,1)
dimnames(s) <- list(variable=rn, rep=NULL)
p <- coef(b); names(p) -> rnp
dim(p) <- c(length(p),1); dimnames(p) <- list(param=rnp)
o <- obs(b)[,1,drop=FALSE]
runit_measure(b, x=s, unit=2, time=1, params=p)
}
}
\author{
Kidus Asfaw
}
