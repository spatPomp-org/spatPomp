##' Iterated Unadapted Bagged Filter (IUBF)
##'
##' An algorithm for estimating the parameters of a spatiotemporal partially-observed Markov process.
##' Running \code{iubf} causes the algorithm to perform a specified number of iterations of unadapted simulations with parameter perturbation and parameter resamplings.
##' At each iteration, unadapted simulations are performed on a perturbed version of the model, in which the parameters to be estimated are subjected to random perturbations at each observation.
##' After cycling through the data, each replicate's weight is calculated and is used to rank the bootstrap replictates. The highest ranking replicates are recycled into the next iteration.
##' This extra variability introduced through parameter perturbation effectively smooths the likelihood surface and combats particle depletion by introducing diversity into particle population.
##' As the iterations progress, the magnitude of the perturbations is diminished according to a user-specified cooling schedule.
##'
##' @name iubf
##' @rdname iubf
##' @include spatPomp_class.R abf.R iter_filter.R
##' @author Kidus Asfaw
##' @family likelihood maximization algorithms
##' @seealso likelihood evaluation algorithms: \code{girf()}, \code{enkf()}, \code{bpfilter()}, \code{abf()}, \code{abfir()}
##' @importFrom stats quantile
##' @importFrom utils head
##' @inheritParams pomp::mif2
##' @inheritParams abf
##' @param Nubf The number of iterations to perform
##' @param Nparam The number of parameters that will undergo the iterated perturbation
##' @param Nrep_per_param The number of replicates used to estimate the likelihood at a parameter
##' @param prop A numeric between 0 and 1. The top \code{prop}*100\% of the parameters are resampled at each observation
##' @return Upon successful completion, \code{iubf()} returns an object of class
##' \sQuote{iubfd_spatPomp}. This object contains the convergence record of the iterative algorithm with
##' respect to the likelihood and the parameters of the model (which can be accessed using the \code{traces}
##' attribute) as well as a final parameter estimate, which can be accessed using the \code{coef()}. The
##' algorithmic parameters used to run \code{iubf()} are also included.
##'
##' @section Methods:
##' The following methods are available for such an object:
##' \describe{
##' \item{\code{\link{coef}}}{ extracts the point estimate }
##' }
##' @references
##'
##' \asfaw2020
##'
##' \ionides2021
##'

NULL

rw.sd <- safecall

setClass(
  "iubf_iter",
  slots=c(
    cond_loglik = 'numeric',
    paramMatrix = 'matrix'
  ),
  prototype=prototype(
    cond_loglik = numeric(0),
    paramMatrix = matrix(0)
  )
)

## define the iubfd_spatPomp class
setClass(
  'iubfd_spatPomp',
  contains='abfd_spatPomp',
  slots=c(
    Nubf = 'integer',
    rw.sd = 'matrix',
    cooling.type = 'character',
    cooling.fraction.50 = 'numeric',
    traces = 'matrix',
    paramMatrix = 'array'
  )
)

setGeneric(
  "iubf",
  function (object, ...)
    standardGeneric("iubf")
)

##' @name iubf-spatPomp
##' @aliases iubf,spatPomp-method
##' @rdname iubf
##' @export
setMethod(
  "iubf",
  signature=signature(object="spatPomp"),
  definition = function (object, Nubf = 1, Nrep_per_param, Nparam, nbhd, prop,
    rw.sd,
    cooling.type = c("geometric","hyperbolic"),
    cooling.fraction.50, tol = (1e-18)^17,
    verbose = getOption("spatPomp_verbose"),...) {

    ep <- paste0("in ",sQuote("iubf"),": ")
    if(missing(Nubf))
      pStop_(ep,sQuote("Nubf")," must be specified")
    if (Nubf <= 0)
      pStop_(ep,sQuote("Nubf")," must be a positive integer")
    if(missing(Nrep_per_param))
      pStop_(ep,"number of replicates, ",
        sQuote("Nrep_per_param"),", must be specified")
    if (missing(rw.sd))
      pStop_(ep,sQuote("rw.sd")," must be specified")
    if (missing(cooling.fraction.50))
      pStop_(ep,sQuote("cooling.fraction.50")," must be specified")
    if (missing(nbhd))
      pStop_(ep,sQuote("nbhd")," must be specified")
    if (missing(Nparam))
      pStop_(ep,sQuote("Nparam")," must be specified")
    if (Nparam<2.5)
      pStop_(ep,sQuote("Nparam")," must be at least 3")
    if (missing(prop))
      pStop_(ep,sQuote("prop")," must be specified")
    cooling.type <- match.arg(cooling.type)
    cooling.fraction.50 <- as.numeric(cooling.fraction.50)
    if (cooling.fraction.50 <= 0 || cooling.fraction.50 > 1)
      pStop_(ep,sQuote("cooling.fraction.50")," must be in (0,1]")

    iubf_internal(
      object=object,
      Nrep_per_param=Nrep_per_param,
      Nparam=Nparam,
      Nubf=Nubf,
      nbhd=nbhd,
      prop=prop,
      rw.sd=rw.sd,
      cooling.type=cooling.type,
      cooling.fraction.50=cooling.fraction.50,
      tol=tol,
      verbose=verbose,
      ...
    )
  }
)

iubf_ubf <- function (object,
  params,
  Nrep_per_param,
  nbhd,
  prop,
  abfiter,
  cooling.fn,
  rw.sd,
  tol = (1e-18)^17,
  .indices = integer(0), verbose,
  .gnsi = TRUE) {
  gnsi <- as.logical(.gnsi)
  verbose <- as.logical(verbose)
  abfiter <- as.integer(abfiter)
  Nparam <- dim(params)[2]
  Nrep_per_param <- as.integer(Nrep_per_param)

  all_times <- time(object,t0=TRUE)
  ntimes <- length(all_times)-1
  nunits <- length(unit_names(object))
  cond_loglik <- vector(length=ntimes)
  prev_meas_weights <- NULL
  pompLoad(object,verbose=FALSE)
  resample_ixs_raw <- rep(1:Nparam)
  params <- params[,resample_ixs_raw]

  i <- 1
#  mcopts <- list(set.seed=TRUE)

  for(nt in seq_len(ntimes)){
    if(verbose && nt %in% c(1,2)) {
      cat("working on observation times ", nt, " in iteration ", abfiter, "\n")
    }
    pmag <- cooling.fn(nt,abfiter)$alpha*rw.sd[,nt]
    params <- .Call(randwalk_perturbation_spatPomp,params,pmag)

    all_params <- params[,rep(1:Nparam, each = Nrep_per_param)]
    tparams <- pomp::partrans(object,all_params,dir="fromEst",.gnsi=gnsi)

    if(!is.null(prev_meas_weights)) num_old_times <- dim(prev_meas_weights)[3]
    else num_old_times <- 0

    if (nt == 1L) {
      X <- rinit(object,params=tparams)
    }
    else X <- X[,resample_ixs]

    jobs_by_param <- foreach::foreach(i=1:Nparam,
      .packages=c("pomp","spatPomp")
    ) %dopar%
      {
        jobX <- rprocess(object,
          x0=X[,((i-1)*Nrep_per_param+1):(i*Nrep_per_param)],
          t0=all_times[nt],
          times=all_times[nt+1],
          params=tparams[,((i-1)*Nrep_per_param+1):(i*Nrep_per_param)],
          .gnsi=gnsi)
        ## determine the weights. returns weights which is a nunits by Np array
        log_cond_densities <- tryCatch(
          vec_dmeasure(
            object,
            y=object@data[,nt,drop=FALSE],
            x=jobX,
            times=all_times[nt+1],
            params=tparams[,((i-1)*Nrep_per_param+1):(i*Nrep_per_param)],
            log=TRUE,
            .gnsi=gnsi
          ),
          error = function (e) pStop_("error in calculation of weights: ",
              conditionMessage(e))
        )[,,1]
        log_cond_densities[is.infinite(log_cond_densities)] <- log(tol)
        gnsi <- FALSE

        log_loc_comb_pred_weights <- array(data = numeric(0), dim=c(nunits, Nrep_per_param))

        for (unit in seq_len(nunits)){
          full_nbhd <- nbhd(object, time = nt, unit = unit)
          log_prod_cond_dens_nt  <- rep(0, Nrep_per_param)
          log_prod_cond_dens_not_nt <- rep(0, Nrep_per_param)
          for (neighbor in full_nbhd){
            neighbor_u <- neighbor[1]
            neighbor_n <- neighbor[2]
            if (neighbor_n == nt)
              if(Nrep_per_param==1){
                log_prod_cond_dens_nt  <- log_prod_cond_dens_nt + log_cond_densities[neighbor_u]
              } else {
                log_prod_cond_dens_nt  <- log_prod_cond_dens_nt + log_cond_densities[neighbor_u, ]
              }
            else{
              ## means prev_meas_weights was non-null, i.e. dim(prev_meas_weights)[3]>=1
              log_prod_cond_dens_not_nt <- log_prod_cond_dens_not_nt +
                prev_meas_weights[neighbor_u,((i-1)*Nrep_per_param+1):(i*Nrep_per_param) ,num_old_times+1-(nt-neighbor_n)]
            }
          }
          log_loc_comb_pred_weights[unit,]  <- log_prod_cond_dens_not_nt + log_prod_cond_dens_nt
        }
        log_wm_times_wp_avgs_by_param <- apply(log_loc_comb_pred_weights +
	  log_cond_densities, c(1), FUN = logmeanexp)
        log_wp_avgs_by_param <- apply(log_loc_comb_pred_weights, c(1), FUN = logmeanexp)
        param_resamp_log_weights <- sum(log_wm_times_wp_avgs_by_param - log_wp_avgs_by_param)
        list(jobX[,,1],log_cond_densities,param_resamp_log_weights)
      }
    X <- do.call(cbind, lapply(seq_along(jobs_by_param), function(j) jobs_by_param[[j]][[1]]))
    log_cond_densities <- do.call(cbind, lapply(seq_along(jobs_by_param), function(j) jobs_by_param[[j]][[2]]))
    param_resamp_log_weights <- do.call(c, lapply(seq_along(jobs_by_param), function(j) jobs_by_param[[j]][[3]]))

####### Quantile resampling
    def_resample <- which(param_resamp_log_weights > quantile(param_resamp_log_weights, 1-prop))
    length_also_resample <- Nparam - length(def_resample)
    if(length(def_resample) > 1){
      also_resample <- sample(def_resample, size = length_also_resample, replace = TRUE,
      prob = rep(1, length(def_resample))) 
    } else if (length(def_resample) == 1){
      also_resample <- rep(def_resample, length_also_resample)
    } else {
      also_resample <- seq_len(Nparam)
    }
    resample_ixs_raw <- c(def_resample, also_resample)
    resample_ixs <- (resample_ixs_raw - 1)*Nrep_per_param
    resample_ixs <- rep(resample_ixs, each = Nrep_per_param)
    resample_ixs <- rep(1:(Nrep_per_param), Nparam) + resample_ixs
    params <- params[,resample_ixs_raw]
    rm(def_resample,also_resample,length_also_resample,resample_ixs_raw)

    ## for next observation time, how far back do we need
    ## to provide the conditional densities, f_{Y_{u,n}|X_{u,n}}?
    max_lookback <- 0
    for(u in seq_len(nunits)){
      all_nbhd_times <- sapply(nbhd(object=object,unit=u,time=nt+1),'[[',2)
      if(length(all_nbhd_times) == 0) next
      smallest_nbhd_time <- min(all_nbhd_times)
      if(nt+1-smallest_nbhd_time > max_lookback) max_lookback <- nt+1-smallest_nbhd_time
    }
    if(max_lookback == 1) prev_meas_weights <- array(log_cond_densities[,resample_ixs],
      dim = c(dim(log_cond_densities),1))
    if(max_lookback > 1){
      prev_meas_weights <- abind::abind(prev_meas_weights[,,(dim(prev_meas_weights)[3]+2-max_lookback):dim(prev_meas_weights)[3],drop=F],
        log_cond_densities,
        along=3)[,resample_ixs,,drop=FALSE]
    }
    cond_loglik[nt] <- logmeanexp(param_resamp_log_weights)
  }
  pompUnload(object,verbose=FALSE)
  new(
    "iubf_iter",
    cond_loglik = cond_loglik,
    paramMatrix=params
  )
}

iubf_internal <- function (object, Nrep_per_param, Nparam, nbhd, Nubf, prop, rw.sd,
  cooling.type, cooling.fraction.50,
  tol = (1e-18)^17,
  verbose = FALSE, .ndone = 0L,
  .indices = integer(0),
  .paramMatrix = NULL,
  .gnsi = TRUE, ...) {

  verbose <- as.logical(verbose)
  p_object <- pomp(object,...,verbose=FALSE)
  object <- new("spatPomp",p_object,
    unit_covarnames = object@unit_covarnames,
    shared_covarnames = object@shared_covarnames,
    runit_measure = object@runit_measure,
    dunit_measure = object@dunit_measure,
    eunit_measure = object@eunit_measure,
    munit_measure = object@munit_measure,
    vunit_measure = object@vunit_measure,
    unit_names=object@unit_names,
    unitname=object@unitname,
    unit_statenames=object@unit_statenames,
    unit_obsnames = object@unit_obsnames)

  gnsi <- as.logical(.gnsi)
  Nubf <- as.integer(Nubf)

  cooling.fn <- mif2.cooling(
    type=cooling.type,
    fraction=cooling.fraction.50,
    ntimes=length(time(object))
  )
  ## initialize the parameter for each rep
  .indices <- integer(0)
  if (is.null(.paramMatrix)) {
    rep_param_init <- coef(object)
    start <- coef(object)
  }
  ## continuation using .paramMatrix not yet implemented
  ## else {
  ##   rep_param_init <- .paramMatrix
  ##   start <- apply(.paramMatrix,1L,mean)
  ## }

  rw.sd <- perturbn.kernel.sd(rw.sd,time=time(object),paramnames=names(start))

  traces <- array(dim=c(Nubf+1,length(start)+1),
    dimnames=list(iteration=seq.int(.ndone,.ndone+Nubf),
      variable=c('loglik',names(start))))
  traces[1L,] <- c(NA,start)

  rep_param_init <- partrans(object,rep_param_init,dir="toEst",.gnsi=gnsi)
  rep_param_init <- array(data = rep_param_init,
    dim = c(length(rep_param_init), Nparam),
    dimnames = list(param = names(rep_param_init), rep = NULL))

  ## iterate the filtering
  for (n in seq_len(Nubf)) {
    out <- iubf_ubf(
      object=object,
      params=rep_param_init,
      Nrep_per_param=Nrep_per_param,
      nbhd=nbhd,
      prop=prop,
      abfiter=.ndone+n,
      cooling.fn=cooling.fn,
      rw.sd=rw.sd,
      tol=tol,
      .indices=.indices,
      verbose=verbose
    )
    gnsi <- FALSE
    rep_param_init <- out@paramMatrix
    out_params_summary <- apply(partrans(object,
      rep_param_init,
      dir="fromEst", .gnsi=.gnsi),1,mean)

    traces[n+1,-c(1)] <- out_params_summary
    traces[n+1,c(1)] <- sum(out@cond_loglik)
    coef(object) <- out_params_summary
    if (verbose) {
      cat("iubf iteration",n,"of",Nubf,"completed","with log-likelihood",sum(out@cond_loglik),"\n")
      print(out_params_summary)
    }
  }
  ## parameter swarm to be outputted
  param_swarm <- partrans(object,
    rep_param_init,
    dir="fromEst", .gnsi=.gnsi)
  pompUnload(object,verbose=FALSE)

  new(
    "iubfd_spatPomp",
    object,
    Nubf=as.integer(Nubf),
    Nrep=as.integer(Nrep_per_param),
    Np=as.integer(1),
    rw.sd=rw.sd,
    cooling.type=cooling.type,
    cooling.fraction.50=cooling.fraction.50,
    traces=traces,
    paramMatrix=param_swarm,
    loglik=sum(out@cond_loglik)
  )

}

