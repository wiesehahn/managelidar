% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plot_extent.R
\name{plot_extent}
\alias{plot_extent}
\title{Plot the extent of lasfiles}
\usage{
plot_extent(path)
}
\arguments{
\item{path}{Either a path to a directory which contains laz files or a single laz file or
the path to a Virtual Point Cloud (.vpc) created with lasR package.}
}
\value{
An interactive map in the viewer
}
\description{
\code{plot_extent} plots the spatial extent (bounding boxes) of lasfiles on an interactive map. The extent is read from the header of lasfiles.
}
\examples{
f <- system.file("extdata", package="managelidar")
plot_extent(f)
}
