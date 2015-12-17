//
//  ViewRecorder.swift
//  Buy
//
//  Created by David Lee on 12/14/15.
//  Copyright © 2015 Sometimes. All rights reserved.
//

import UIKit
import BrightFutures

class ViewRecorder: NSObject {
	func recordView(view: UIView) -> RecordingContext {
		return RecordingContextImpl(view: view)
	}
}

protocol RecordingContext {
	func snapshot() -> UIImage
	func pauseRecording()
	func resumeRecording()
	func exportRecording() -> Future<NSURL, ConversionError>
}


class RecordingContextImpl: NSObject, RecordingContext {
	// Resources
	unowned let view: UIView
	var displayLink: CADisplayLink!

	// State
	var frames: [UIImage] = []
	var isRecording: Bool = false {
		didSet {
			guard oldValue != isRecording else { return }

			if isRecording {
				displayLink.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSRunLoopCommonModes)
			} else {
				displayLink.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSRunLoopCommonModes)
			}
		}
	}

	init(view: UIView) {
		self.view = view
		super.init()
		self.displayLink = CADisplayLink(target: self, selector: "recordLoop:")
	}

	func pauseRecording() {
		isRecording = false
	}

	func resumeRecording() {
		isRecording = true
	}

	func exportRecording() -> Future<NSURL, ConversionError> {
		return convertImageSequenceToVideo(frames, outputVideoSize: _renderSize).flatMap { fileURL -> Future<NSURL, ConversionError> in
			return saveVideoAtURLToCameraRoll(fileURL).mapError { ConversionError.ExternalError($0) }
//				.onSuccess { url in
//					print("Saved to camera roll!", url)
//				}.onFailure { err in
//					print("Failed to save to camera roll: ", err)
//				}
		}
//			.onSuccess { _ in
//				print("Exported to video.")
//			}.onFailure {
//				print("Failed to export to video: ", $0)
//			}
	}

	func snapshot() -> UIImage {
		UIGraphicsBeginImageContextWithOptions(_renderSize, true, 1.0)
		view.drawViewHierarchyInRect(CGRect(origin: view.bounds.origin, size: _renderSize), afterScreenUpdates: false)
		let result = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return result
	}


	// Internals

	var _lastTimestamp: CFTimeInterval?
	internal func recordLoop(displayLink: CADisplayLink) {
		print("Frame duration: ", displayLink.duration)

		if let lastTimestamp = _lastTimestamp {
			print("Timestamp delta", displayLink.timestamp - lastTimestamp)
		}
		_appendFrame(snapshot())
		_lastTimestamp = displayLink.timestamp
	}

	private func _appendFrame(frame: UIImage) {
		frames.append(frame)
	}

	private func _coerceSize(size: CGSize) -> CGSize {
		let alignment: CGFloat = 16.0
		let newWidth = size.width + (alignment - size.width % alignment)
		assert(newWidth % alignment == 0.0)

		return CGSize(width: newWidth, height: size.height * (newWidth / size.width))
	}

	private var _renderSize: CGSize {
		return _coerceSize(view.bounds.size)
	}

	deinit {
		displayLink.invalidate()
	}
}