//
//  CameraRollCommunicator.swift
//  ViewRecorder
//
//  Created by David Lee on 12/16/15.
//  Copyright © 2015 David Lee. All rights reserved.
//

import Foundation
import BrightFutures
import AssetsLibrary

func saveVideoAtURLToCameraRoll(videoURL: NSURL) -> Future<NSURL, NSError> {
	let promise = Promise<NSURL, NSError>()

	let library: ALAssetsLibrary = ALAssetsLibrary()
	if library.videoAtPathIsCompatibleWithSavedPhotosAlbum(videoURL) {
		library.writeVideoAtPathToSavedPhotosAlbum(videoURL) { (newURL, error) -> Void in
			if newURL == nil {
				promise.failure(error)
			} else {
				promise.success(newURL)
			}
		}
	}

	return promise.future
}