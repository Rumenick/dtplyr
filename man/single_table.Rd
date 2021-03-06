% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/step.R, R/step-group.R
\name{single_table}
\alias{single_table}
\alias{group_by.dtplyr_step}
\title{Single table operations}
\usage{
\method{group_by}{dtplyr_step}(.data, ..., add = FALSE, arrange = TRUE)
}
\arguments{
\item{.data}{A data.table}

\item{...}{In \code{group_by()}, variables or computations to group by.
In \code{ungroup()}, variables to remove from the grouping.}

\item{add}{When \code{FALSE}, the default, \code{group_by()} will
override existing groups. To add to the existing groups, use
\code{.add = TRUE}.

This argument was previously called \code{add}, but that prevented
creating a new grouping variable called \code{add}, and conflicts with
our naming conventions.}

\item{arrange}{If \code{TRUE}, will automatically arrange the output of
subsequent grouped operations by group. If \code{FALSE}, output order will be
left unchanged. In the generated data.table code this switches between
using the \code{keyby} (\code{TRUE}) and \code{by} (\code{FALSE}) arguments.}
}
\description{
This documents differences between standard dplyr verbs and their
data.table instantiation.
}
